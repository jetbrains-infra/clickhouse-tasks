FROM amazonlinux:latest

RUN yum install aws-cli -y
ADD ./entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]

