#!/bin/bash
set -e

ENVIRONMENT=$1
IMAGE_TAG=$2

if [ -z "$ENVIRONMENT" ] || [ -z "$IMAGE_TAG" ]; then
  echo "Uso: ./rollback.sh <environment> <image-tag>"
  echo "Exemplo: ./rollback.sh staging staging-abc1234"
  exit 1
fi

if [ "$ENVIRONMENT" == "staging" ]; then
  HOST=$STAGING_HOST
  CONTAINER_NAME="lacrei-staging"
  NODE_ENV="staging"
elif [ "$ENVIRONMENT" == "production" ]; then
  HOST=$PRODUCTION_HOST
  CONTAINER_NAME="lacrei-production"
  NODE_ENV="production"
else
  echo "Environment invalido. Use: staging ou production"
  exit 1
fi

echo "Iniciando rollback para $ENVIRONMENT com imagem $IMAGE_TAG..."

ssh -i "$SSH_KEY_PATH" ubuntu@$HOST << EOF
  TOKEN=\$(aws ecr get-login-password --region $AWS_REGION)
  docker login --username AWS --password \$TOKEN $ECR_REPOSITORY
  docker pull $ECR_REPOSITORY:$IMAGE_TAG
  docker stop $CONTAINER_NAME || true
  docker rm $CONTAINER_NAME || true
  docker run -d \
    --name $CONTAINER_NAME \
    --restart always \
    -p 3000:3000 \
    -e NODE_ENV=$NODE_ENV \
    -e APP_VERSION=$IMAGE_TAG \
    $ECR_REPOSITORY:$IMAGE_TAG
  echo "Rollback concluido!"
EOF
