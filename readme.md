apt install wget
wget https://raw.githubusercontent.com/ykhedar/install/refs/heads/main/install.sh
bash install.sh --setup --install-dev
cd .skyclient/
docker login
tailscale up
export REACT_APP_DEVICE_HOST=100.69.54.97
export REACT_APP_DEVICE_PORT=8001
export REACT_APP_ENVIRONMENT=development
export PUBLIC_PATH=/ui/
docker compose up
   