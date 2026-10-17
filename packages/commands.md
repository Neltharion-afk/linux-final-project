# Пакетные менеджеры — листинг команд

## 1. Добавление стороннего репозитория (Docker)

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update

## 2. Установка пакета из стороннего репозитория
bash
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

## 3. Установка локального .deb-пакета
bash
cd /tmp
wget http://archive.ubuntu.com/ubuntu/pool/universe/s/sl/sl_5.02-1_amd64.deb
sudo dpkg -i sl_5.02-1_amd64.deb

## 4. Удаление пакета через dpkg
bash
sudo dpkg -r sl

