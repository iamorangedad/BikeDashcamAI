#!/bin/bash

echo "Deploying BikeDashcamAI backend with Ultralytics image and namespace..."

# Create namespace
echo "Creating namespace..."
kubectl create namespace bike-dashcam --dry-run=client -o yaml | kubectl apply -f -

# Apply Kubernetes configurations
echo "Applying Kubernetes configurations..."

kubectl apply -f k8s/backend-config.yaml
kubectl apply -f k8s/backend-deployment.yaml

if [ $? -eq 0 ]; then
    echo "✅ Kubernetes deployment successful"
    echo "🚀 Backend is available at:"
    echo "   - ClusterIP: http://bike-dashcam-backend-service.bike-dashcam:8000"
    echo "   - NodePort: http://localhost:30080"
    echo "   - Health check: http://localhost:30080/health"
    echo ""
    echo "📱 RTSP Stream URL: rtsp://10.0.0.75:8554/stream"
    echo "🔧 Using Ultralytics Jetson image with code mounting"
    echo "📁 Backend code mounted at: /workspace/backend"
    echo "📁 Output files at: ./outputs (local)"
    echo ""
    echo "🔍 Check deployment status:"
    echo "   kubectl get pods -n bike-dashcam -l app=bike-dashcam-backend"
    echo "   kubectl logs -f -n bike-dashcam deployment/bike-dashcam-backend"
    echo ""
    echo "⚠️  Note: Make sure NVIDIA GPU operator is installed for GPU support"
    echo "💻 Code changes in ./backend will be reflected immediately in the pod"
else
    echo "❌ Kubernetes deployment failed"
    exit 1
fi