#!/bin/bash
set -e

apt update -y
apt install -y docker.io unzip curl

systemctl start docker
systemctl enable docker
usermod -aG docker ubuntu

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws

echo "Setup concluido" >> /var/log/user_data.log
