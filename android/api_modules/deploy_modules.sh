#!/bin/bash
# Deploy script for API modules

SERVER="root@167.86.89.229"
REMOTE_DIR="/root/arabica_app/loyalty-proxy/api"

echo "Creating api directory on server..."
ssh $SERVER "mkdir -p $REMOTE_DIR"

echo "Copying API modules..."
scp *.js $SERVER:$REMOTE_DIR/

echo "Setting permissions..."
ssh $SERVER "chmod 644 $REMOTE_DIR/*.js"

echo "Backing up current index.js..."
ssh $SERVER "cp /root/arabica_app/loyalty-proxy/index.js /root/arabica_app/loyalty-proxy/index.js.backup_$(date +%Y%m%d_%H%M%S)"

echo "Deploying new modular index.js..."
scp index.js $SERVER:/root/arabica_app/loyalty-proxy/index_new.js

echo "Testing new index.js..."
ssh $SERVER "cd /root/arabica_app/loyalty-proxy && node -c index_new.js"

echo "If test passed, run:"
echo "  ssh $SERVER 'cd /root/arabica_app/loyalty-proxy && mv index_new.js index.js && pm2 restart loyalty-proxy'"

echo "Done!"
