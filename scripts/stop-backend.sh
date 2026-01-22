#!/bin/bash

echo "Stopping BikeDashcamAI backend deployment..."

# Delete deployments and services
echo "Deleting deployments and services..."
kubectl delete -f k8s/backend-deployment-namespace.yaml --ignore-not-found=true
kubectl delete -f k8s/backend-config.yaml --ignore-not-found=true

# Optional: Delete namespace
read -p "Delete namespace 'bike-dashcam'? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Deleting namespace..."
    kubectl delete namespace bike-dashcam --ignore-not-found=true
fi

echo "✅ Backend deployment stopped"