FROM ubuntu:22.04
RUN apt-get update && apt-get install -y curl bash
RUN curl -fsSL https://cli.clawhub.io/install.sh | bash || true
WORKDIR /app
COPY clawhub-monitor-all.sh .
COPY monitor-config.sh /root/clawhub-monitor.sh
RUN chmod +x clawhub-monitor-all.sh
CMD ["bash", "clawhub-monitor-all.sh"]
