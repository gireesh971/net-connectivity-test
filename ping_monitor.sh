#!/bin/bash

counter=0
error_counter=0
was_down=0
router_status=""
last_router_status=""
down_start_time=0
success_interval=60  # Log success every 5 minutes (60 * 5 seconds)
stats_interval=17280  # 24 hours = 24*60*60/5 = 17280 checks
stats_counter=0
start_time=$(date)
exec > >(tee -a "ping_monitor_$(date +%Y%m%d_%H%M%S).log") 2>&1

while true; do
    stats_counter=$((stats_counter + 1))
    
    if curl -s --max-time 3 https://httpbin.org/ip > /dev/null 2>&1 || ping -c 1 -W 3 8.8.8.8 > /dev/null 2>&1 || ping -c 1 -W 3 1.1.1.1 > /dev/null 2>&1; then
        counter=$((counter + 1))
        
        # If we were down and now we're back up, calculate downtime and send notification
        if [ $was_down -eq 1 ]; then
            current_time=$(date +%s)
            downtime_seconds=$((current_time - down_start_time))
            downtime_minutes=$((downtime_seconds / 60))
            
            if [ $downtime_minutes -gt 0 ]; then
                downtime_msg="${downtime_minutes} minutes"
            else
                downtime_msg="${downtime_seconds} seconds"
            fi
            
            if ! curl -s --retry 2 --retry-delay 2 -d "Connection restored at $(date '+%I:%M:%S %p'). Was down for ${downtime_msg}. ${router_status}" ntfy.sh/gpuru > /dev/null 2>&1; then
                echo "$(date '+%I:%M:%S %p'): ERROR - Failed to send notification after 3 attempts"
            fi
            was_down=0
            router_status=""
        fi
        
        printf "."
        if [ $((counter % success_interval)) -eq 0 ]; then
            echo ""
            echo "$(date '+%I:%M:%S %p'): Connectivity OK (checked $counter times)"
        fi
    else
        error_counter=$((error_counter + 1))
        
        # Check router connectivity on every error
        if ping -c 1 -W 3 10.0.0.1 > /dev/null 2>&1 || ping -c 1 -W 3 192.168.68.1 > /dev/null 2>&1; then
            current_router_status="Router reachable"
        else
            current_router_status="Router unreachable"
        fi
        
        # If this is the first failure, record the start time
        if [ $was_down -eq 0 ]; then
            down_start_time=$(date +%s)
            was_down=1
            router_status="$current_router_status - $([ "$current_router_status" = "Router reachable" ] && echo "Internet issue" || echo "Local network issue")"
            echo ""
            echo "$(date '+%I:%M:%S %p'): $router_status"
        else
            # Track if router status changed during outage
            if [ "$current_router_status" != "$last_router_status" ]; then
                echo ""
                echo "$(date '+%I:%M:%S %p'): Router status changed: $current_router_status"
            fi
        fi
        
        last_router_status="$current_router_status"
        
        echo ""
        echo "$(date '+%I:%M:%S %p'): ERROR - Failed connectivity tests (HTTP httpbin.org, ping 8.8.8.8 & 1.1.1.1) - $current_router_status"
    fi
    
    # Every 5 minutes, show 24-hour stats
    if [ $((stats_counter % success_interval)) -eq 0 ]; then
        total_checks=$((counter + error_counter))
        if [ $total_checks -gt 0 ]; then
            error_percent=$(( (error_counter * 100) / total_checks ))
            echo ""
            echo "$(date '+%I:%M:%S %p'): Started: $start_time, 24-hour stats - Success: $counter, Errors: $error_counter, Error rate: ${error_percent}%"
        fi
        
        # Reset counters every 24 hours
        if [ $stats_counter -ge $stats_interval ]; then
            counter=0
            error_counter=0
            stats_counter=0
        fi
    fi
    
    sleep 5
done