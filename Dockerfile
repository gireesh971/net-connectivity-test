FROM ubuntu:22.04
RUN apt-get update && apt-get install -y dnsperf && rm -rf /var/lib/apt/lists/*
ENTRYPOINT ["dnsperf"]

