# BikeDashcamAI Backend Kubernetes Deployment

## Overview
This directory contains Kubernetes deployment files for the BikeDashcamAI backend service using the Ultralytics Jetson image with code mounting for development.

## Files
- `backend-deployment-namespace.yaml` - Main deployment with namespace and services
- `backend-config.yaml` - ConfigMap for environment variables
- `deploy-backend.sh` - Automated deployment script
- `stop-backend.sh` - Script to stop and cleanup deployment

## Quick Start

### Prerequisites
- Kubernetes cluster with NVIDIA GPU support
- NVIDIA GPU Operator installed
- kubectl configured
- Host path access for code mounting

### Deployment
```bash
# Deploy the backend service
./scripts/deploy-backend.sh

# Stop the backend service
./scripts/stop-backend.sh
```

### Access the Service
- **NodePort**: `http://localhost:30080`
- **Health Check**: `http://localhost:30080/health`
- **WebSocket**: `ws://localhost:30080/ws/{client_id}`
- **Namespace**: `bike-dashcam`

### RTSP Configuration
The backend is configured to connect to the mobile device's RTSP stream:
- **URL**: `rtsp://10.0.0.75:8554/stream`
- **Protocol**: RTSP over TCP
- **Format**: H.264 video stream

## Architecture

### Container Image
- **Base Image**: `ultralytics/ultralytics:latest-jetson-jetpack6`
- **GPU Support**: NVIDIA CUDA with JetPack 6
- **Pre-installed**: Ultralytics YOLO, OpenCV, PyTorch

### Code Mounting
- **Host Path**: `./backend` → `/workspace/backend`
- **Output Path**: `./outputs` → `/workspace/backend/outputs`
- **Live Reload**: Code changes reflected immediately

### Environment Variables

| Variable | Value | Description |
|----------|-------|-------------|
| `RTSP_STREAM_URL` | `rtsp://10.0.0.75:8554/stream` | Mobile device RTSP stream URL |
| `ENVIRONMENT` | `development` | Runtime environment |
| `LOG_LEVEL` | `INFO` | Logging verbosity |
| `PYTHONPATH` | `/workspace/backend` | Python module path |
| `FPS` | `30` | Video processing frame rate |
| `OUTPUT_WIDTH` | `1280` | Output video width |
| `OUTPUT_HEIGHT` | `720` | Output video height |

## GPU Configuration

### Resource Requests
- **GPU**: 1 NVIDIA GPU
- **Memory**: 1Gi request, 4Gi limit
- **CPU**: 500m request, 2000m limit

### NVIDIA Operator Setup
```bash
# Install NVIDIA GPU Operator (if not already installed)
kubectl create ns gpu-operator
helm repo add nvidia https://nvidia.github.io/gpu-operator
helm install gpu-operator nvidia/gpu-operator -n gpu-operator
```

## Development Workflow

### 1. Code Development
Edit files in `./backend/` - changes are immediately reflected in the running pod.

### 2. Testing
```bash
# Check pod status
kubectl get pods -n bike-dashcam -l app=bike-dashcam-backend

# View logs
kubectl logs -f -n bike-dashcam deployment/bike-dashcam-backend

# Access container shell
kubectl exec -it -n bike-dashcam deployment/bike-dashcam-backend -- bash
```

### 3. Output Files
Processed videos are saved to `./outputs/` on the host machine.

## Services

### ClusterIP Service
- **Name**: `bike-dashcam-backend-service`
- **Port**: 8000
- **Target**: Port 8000 in pods

### NodePort Service
- **Name**: `bike-dashcam-backend-nodeport`
- **Port**: 8000
- **NodePort**: 30080
- **External Access**: `http://localhost:30080`

## Monitoring

### Health Checks
- **Liveness Probe**: `/health` after 60s initial delay
- **Readiness Probe**: `/health` after 30s initial delay

### Debug Commands
```bash
# Describe pod
kubectl describe pod -n bike-dashcam -l app=bike-dashcam-backend

# Check events
kubectl get events -n bike-dashcam --field-selector involvedObject.name=bike-dashcam-backend

# Test RTSP connectivity
kubectl exec -it -n bike-dashcam deployment/bike-dashcam-backend -- ping 10.0.0.75

# Check GPU allocation
kubectl exec -it -n bike-dashcam deployment/bike-dashcam-backend -- nvidia-smi
```

## Troubleshooting

### Common Issues
1. **GPU Not Available**: Ensure NVIDIA GPU Operator is installed
2. **RTSP Connection Failed**: Verify mobile device accessibility
3. **Code Mount Issues**: Check host path permissions
4. **Pod Crash Loop**: Review logs for dependency issues

### Recovery Commands
```bash
# Restart deployment
kubectl rollout restart -n bike-dashcam deployment/bike-dashcam-backend

# Scale to zero and back
kubectl scale -n bike-dashcam deployment/bike-dashcam-backend --replicas=0
kubectl scale -n bike-dashcam deployment/bike-dashcam-backend --replicas=1
```

## Local Development Alternative

For development without Kubernetes:
```bash
cd backend
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```