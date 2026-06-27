FROM ubuntu:22.04
RUN apt-get update && apt-get install -y curl bash
WORKDIR /app
COPY clawhub-monitor-all.sh .
RUN chmod +x clawhub-monitor-all.sh
CMD ["bash", "clawhub-monitor-all.sh"]
