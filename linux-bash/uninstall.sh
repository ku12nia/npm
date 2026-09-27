#!/bin/bash

echo "=========================================================="
echo "🗑️ 1. Removing Argo CD from Kubernetes"
echo "=========================================================="
echo "Cleaning up Applications and Projects (to avoid stuck namespaces)..."
kubectl delete applications --all -n argocd --ignore-not-found=true
kubectl delete appprojects --all -n argocd --ignore-not-found=true

echo "Removing all Argo CD installation resources..."
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --ignore-not-found=true

echo "Removing namespace argocd..."
kubectl delete namespace argocd --ignore-not-found=true

echo "Removing remaining Custom Resource Definitions (CRD)..."
kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io applicationsyncwindows.argoproj.io --ignore-not-found=true

echo ""
echo "=========================================================="
echo "🛑 2. Stopping Jenkins, PostgreSQL, and pgAdmin (Docker)"
echo "=========================================================="
docker compose down

echo ""
echo "=========================================================="
echo "✅ Done! Uninstallation successful."
echo "=========================================================="
echo "All services in Docker and Argo CD on Kubernetes have been cleaned up."
echo "=========================================================="