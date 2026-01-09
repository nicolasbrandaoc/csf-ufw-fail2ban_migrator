#!/bin/bash

# Cores para facilitar a leitura
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # Sem cor

# Função para pausar e pedir confirmação
confirm_step() {
    echo -e "\n${YELLOW}>> Pressione [ENTER] para seguir para a próxima etapa ou [CTRL+C] para cancelar...${NC}"
    read -r
}

# Função para cabeçalhos
print_header() {
    clear
    echo -e "${CYAN}========================================================${NC}"
    echo -e "${CYAN}  $1 ${NC}"
    echo -e "${CYAN}========================================================${NC}"
}

# 1. Verificação de privilégios
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Erro: Por favor, execute como root (sudo).${NC}"
  exit
fi

# --- ETAPA 0: BACKUP ---
print_header "ETAPA 0/9: CRIANDO BACKUP DE SEGURANÇA"
if [ -d "/etc/csf" ]; then
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    tar -czf /root/backup_csf_$TIMESTAMP.tar.gz /etc/csf /etc/lfd 2>/dev/null
    echo -e "${GREEN}OK: Backup criado em /root/backup_csf_$TIMESTAMP.tar.gz${NC}"
else
    echo -e "${YELLOW}Aviso: CSF não instalado, pulando backup.${NC}"
fi
confirm_step

# --- ETAPA 1: INSTALAÇÃO ---
print_header "ETAPA 1/9: ATUALIZANDO SISTEMA E INSTALANDO FAIL2BAN"
echo -e "${YELLOW}Executando apt update e instalando dependências...${NC}"
apt update -qq && apt install fail2ban ufw -y -qq
echo -e "${GREEN}OK: Dependências instaladas.${NC}"
confirm_step

# --- ETAPA 2: JAIL.LOCAL ---
print_header "ETAPA 2/9: CONFIGURANDO JAIL.LOCAL"
cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = -1
findtime = 10m
maxretry = 5
backend = systemd
banaction = ufw
banaction_allports = ufw
ignoreip = 127.0.0.1/8 52.67.6.27

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 4
bantime = -1

[recidive]
enabled  = true
logpath  = /var/log/fail2ban.log
interval = 1d
maxretry = 3
bantime  = 1w
findtime = 1d

[pam-generic]
enabled  = true
filter   = pam-generic
logpath  = /var/log/auth.log
maxretry = 3
bantime  = 1h

[nginx-http-auth]
enabled = true
[nginx-badbots]
enabled = true
[nginx-noscript]
enabled = true
[nginx-nohome]
enabled = true

[nginx-dos]
enabled = true
port = http,https
logpath = /var/log/nginx/access.log
maxretry = 300
findtime = 1m
bantime = 1h

[apache-auth]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/error.log
maxretry = 5

[apache-badbots]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/access.log
bantime  = 48h
maxretry = 1

[apache-noscript]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/error.log
maxretry = 3

[apache-overflow]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/error.log
maxretry = 2

[vsftpd]
enabled  = true
port     = ftp,ftp-data,ftps,ftps-data
logpath  = /var/log/vsftpd.log
maxretry = 5
bantime  = -1
EOF
echo -e "${GREEN}OK: jail.local configurado.${NC}"
confirm_step

# --- ETAPA 3: FILTROS ---
print_header "ETAPA 3/9: CRIANDO FILTROS PERSONALIZADOS"
cat <<EOF > /etc/fail2ban/filter.d/nginx-dos.conf
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD).*HTTP.*"$
EOF
cp /etc/fail2ban/filter.d/nginx-dos.conf /etc/fail2ban/filter.d/apache-dos.conf

cat <<EOF > /etc/fail2ban/filter.d/nginx-badbots.conf
[Definition]
failregex = ^<HOST> -.*"GET .* HTTP/.*" 403 .* "(?:Atomic_Email_Hunter|Jorgee|PycURL|libwww-perl|Whacker)"$
EOF

cat <<EOF > /etc/fail2ban/filter.d/nginx-noscript.conf
[Definition]
failregex = ^<HOST> -.*"GET .*\.(?:php|asp|exe|pl|cgi) HTTP/.*" 404
EOF

cat <<EOF > /etc/fail2ban/filter.d/nginx-nohome.conf
[Definition]
failregex = ^<HOST> -.*"GET /~.* HTTP/.*" 404
EOF

cat <<EOF > /etc/fail2ban/filter.d/apache-overflow.conf
[Definition]
failregex = ^\[\] \[error\] \[client <HOST>\] (?:request failed: URI too long|invalid request-line)
EOF
echo -e "${GREEN}OK: Filtros filter.d criados.${NC}"
confirm_step

# --- ETAPA 4: PORTAS ---
print_header "ETAPA 4/9: MIGRANDO PORTAS DO CSF"
CSF_CONF="/etc/csf/csf.conf"
if [ -f "$CSF_CONF" ]; then
    TCP_PORTS=$(grep "^TCP_IN =" "$CSF_CONF" | cut -d'"' -f2 | sed 's/ //g')
    UDP_PORTS=$(grep "^UDP_IN =" "$CSF_CONF" | cut -d'"' -f2 | sed 's/ //g')
    
    IFS=',' read -ra T_ADDR <<< "$TCP_PORTS"
    for p in "${T_ADDR[@]}"; do [ ! -z "$p" ] && ufw allow "$p/tcp" > /dev/null; done
    
    IFS=',' read -ra U_ADDR <<< "$UDP_PORTS"
    for p in "${U_ADDR[@]}"; do [ ! -z "$p" ] && ufw allow "$p/udp" > /dev/null; done
    echo -e "${GREEN}OK: Portas TCP e UDP transferidas para o UFW.${NC}"
else
    echo -e "${RED}Erro: Arquivo csf.conf não encontrado.${NC}"
fi
confirm_step

# --- ETAPA 5: LISTAS ---
print_header "ETAPA 5/9: MIGRANDO WHITELIST E BLACKLIST"
echo -e "${YELLOW}Lendo arquivos de IPs do CSF...${NC}"
[ -f /etc/csf/csf.allow ] && grep -v "^#" /etc/csf/csf.allow | while read ip; do [ ! -z "$ip" ] && ufw allow from $(echo $ip | awk '{print $1}') > /dev/null; done
[ -f /etc/csf/csf.deny ] && grep -v "^#" /etc/csf/csf.deny | while read ip; do [ ! -z "$ip" ] && ufw insert 1 deny from $(echo $ip | awk '{print $1}') to any > /dev/null; done
echo -e "${GREEN}OK: Whitelist e Blacklist migradas.${NC}"
confirm_step

# --- ETAPA 6: DESINSTALAÇÃO ---
print_header "ETAPA 6/9: DESINSTALANDO CSF/LFD"
if [ -d "/etc/csf" ]; then
    echo -e "${YELLOW}Executando script de desinstalação do CSF...${NC}"
    cd /etc/csf && sh uninstall.sh > /dev/null 2>&1
    rm -rf /etc/csf /var/lib/csf /etc/lfd
    cd ~
    echo -e "${GREEN}OK: CSF removido.${NC}"
else
    echo -e "${YELLOW}CSF já não estava presente.${NC}"
fi
confirm_step

# --- ETAPA 7: ATIVAÇÃO ---
print_header "ETAPA 7/9: ATIVANDO FIREWALL E FAIL2BAN"
ufw --force enable
systemctl restart fail2ban
systemctl enable fail2ban
echo -e "${GREEN}OK: Firewall e Fail2Ban Ativos.${NC}"
confirm_step

# --- RELATÓRIO FINAL ---
print_header "9/9: MIGRAÇÃO CONCLUÍDA - RELATÓRIO DE AUDITORIA"

echo -e "${YELLOW}>>> STATUS DO FAIL2BAN (Jails Ativas):${NC}"
sudo fail2ban-client status
echo -e "\n${CYAN}--------------------------------------------------------${NC}"

echo -e "${YELLOW}>>> STATUS DO FIREWALL UFW (Regras Aplicadas):${NC}"
sudo ufw status numbered
echo -e "\n${CYAN}--------------------------------------------------------${NC}"

echo -e "${GREEN}Backup de segurança: /root/backup_csf_$TIMESTAMP.tar.gz${NC}"
echo -e "${YELLOW}Hardening finalizado. Verifique a lista acima para validar as portas.${NC}\n"
