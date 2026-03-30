#!/usr/bin/env bash
if [ "$#" -ne 1 ]; then
    echo "Error: Missing destination folder argument."
    echo "Usage: $0 <destinationFolder>"
    exit 1
fi

if [ -z "${NODE_ID:-}" ]; then
  echo "Error: NODE_ID environment variable is not set."
  echo "Example: export NODE_ID=1000000001"
  exit 1
fi

if [ "$NODE_ID" -lt 1000000001 ] || [ "$NODE_ID" -gt 1000000020 ]; then
  echo "Error: NODE_ID must be between 1000000001 and 1000000020 (got: $NODE_ID)."
  exit 1
fi

echo "Generating a new RSA key and a 60-day self-signed certificate."

NODE_NAME="node$(($NODE_ID + 1))"
FOLDER=$1

PUBLIC_NAME="s-public-$NODE_NAME"
PRIVATE_NAME="s-private-$NODE_NAME"

openssl genrsa -out "$FOLDER/$PRIVATE_NAME.pem" 3072
openssl req -new -x509 -days 60 -key "$FOLDER/$PRIVATE_NAME.pem" -out "$FOLDER/$PUBLIC_NAME.pem"

echo ""
echo "Generated files:"
echo "- Private key: $FOLDER/$PRIVATE_NAME.pem"
echo "- Certificate: $FOLDER/$PUBLIC_NAME.pem"