# CSF to Fail2Ban + UFW Migrator 🛡️

Este script automatiza a migração de segurança de servidores Linux, substituindo o **ConfigServer Security & Firewall (CSF)** pelo **Fail2Ban** integrado ao **UFW**. 

Ideal para administradores que buscam uma solução de segurança dinâmica, com banimentos permanentes e proteção específica para serviços Web (Nginx/Apache).

## 🚀 Funcionalidades
* **Backup Automático:** Cria um `.tar.gz` de todas as configs do CSF antes de qualquer alteração.
* **Migração de Portas:** Lê o `csf.conf` e abre as mesmas portas no UFW.
* **Whitelist/Blacklist:** Transfere IPs do `csf.allow` e `csf.deny` para o UFW.
* **Jails Customizadas:** Configura proteção contra DoS, Badbots e Brute-force.
* **Banimento Permanente:** Configurado para banir IPs por tempo indeterminado (`bantime = -1`).
* **Interface Interativa:** Processo passo a passo com cores e confirmações manuais.

## 📋 Pré-requisitos
* Ubuntu ou Debian (testado em Ubuntu 22.04/24.04).
* Acesso root ou sudo.

## 📥 Como baixar e usar

Para rodar diretamente via terminal em qualquer servidor:

# 1. Baixar o script de migração
wget https://raw.githubusercontent.com/nicolasbrandaoc/csf-ufw-fail2ban_migrator/main/migrate.sh

# 2. Dar permissão de execução
chmod +x migrate.sh

# 3. Executar o migrador (como root)
sudo ./migrate.sh
