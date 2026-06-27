FROM node:20
RUN apt-get update && apt-get install -y curl bash
RUN npm install -g clawhub
WORKDIR /app
COPY clawhub-monitor-all.sh .
COPY monitor-config.sh /root/clawhub-monitor.sh
COPY entrypoint.sh .
RUN chmod +x clawhub-monitor-all.sh entrypoint.sh
CMD ["bash", "entrypoint.sh"]
