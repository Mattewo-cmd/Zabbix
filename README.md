# Documentation d'Installation : Zabbix (7.4.11)

**Contexte :** Mettre en place un serveur de supervision Zabbix.

---

## 1. Préparation et installation

### 1.1 Installation ISO
* **OS :** Debian 13.1 (Version LTS).
* Vérifier l’intégrité de l’image ISO avant installation.
* Lancer l’installation standard.

### 1.2 Paramétrages réseau
* **IP :** `{IP}/{CIDR}`
* **Gateway :** `{Adresse_IP_Gateway}`
* **Serveur DNS :** `{Windows_Server_rôle_DNS}`
* **Nom FQDN :** `{nom_DNS_du_server}.{nom_de_domaine}`

### 1.3 Configuration machine
* Joindre le poste au domaine (Domaine AD).
* Définir les utilisateurs (ex: `root`, `infra`, etc.).

### 1.4 Gestion du disque
* Mise en place du partitionnement avec **LVM**.
* Points de montage recommandés : `/home`, `/var`, `/tmp` sur des partitions séparées.

### 1.5 Extension de partition
Se référer à la documentation interne : [Étendre un disque LVM](./Extend_Part.md).

### 1.6 Renommer un volume group (VG)

Se référer à la documentation interne : [Renommer un VG (Volume Groupe) LVM](./Rename_VG.md)


### 1.7 Configuration des agents et du pare-feu
* Déployer les agents machine (Veeam, Supervision, etc.).
* Ajouter les règles nécessaires au pare-feu.
* Vérifier la communication avec Internet et le Serveur DNS.

---

## 2. Installation et configuration de Graylog

### 2.1 Prérequis
* Serveur sous Linux (Debian 13).
* Accès administrateur (`root` ou `sudo`).
* Répertoire d'installation pour les conteneurs préparé.

### 2.2 Installation de Docker
1.  Installation des dépendances :
    ```bash
    sudo apt-get install apt-transport-https ca-certificates curl gnupg2
    ```
2.  Ajouter le dépôt officiel Docker :
    ```bash
    curl -fsSL [https://download.docker.com/linux/debian/gpg](https://download.docker.com/linux/debian/gpg) | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] [https://download.docker.com/linux/debian](https://download.docker.com/linux/debian) $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list

    apt-get update
    ```
3.  Installation des paquets Docker :
    ```bash
    apt-get install docker-ce docker-ce-cli containerd.io
    ```
4.  Activation au démarrage :
    ```bash
    systemctl enable docker
    ```

### 2.3 Mise en place des conteneurs

1.  Créer le dossier d'installation :
    ```bash
    mkdir -p /opt/zabbix
    cd /opt/zabbix
    ```
2.  Récupérer les images Docker (Versions : Graylog v7.0.4, MongoDB v8.2.5) :
    ```bash
    docker pull zabbix/zabbix-agent2:alpine-7.4.11
    docker pull zabbix/zabbix-web-nginx-mysql:alpine-7.4.11
    docker pull zabbix/zabbix-server-mysql:alpine-7.4.11
    docker pull mysql:9.6.0
    ```
3. Créer le fichier `.env`

```bash
MYSQL_PASSWORD=mysqlpassword
MYSQL_ROOT_PASSWORD=mysqlrootpassword
```

4. Créer le fichier `docker-compose.yml` complet.

```yaml
services:
  # Base de données MySQL 9.6.0
  zabbix-db:
    image: mysql:9.6.0
    container_name: zabbix-db
    restart: always
    command: --character-set-server=utf8mb4 --collation-server=utf8mb4_bin --log-bin-trust-function-creators=1
    volumes:
      - ./mysql_data:/var/lib/mysql
    environment:
      MYSQL_DATABASE: zabbix
      MYSQL_USER: zabbix
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-p${MYSQL_ROOT_PASSWORD}"]
      interval: 5s
      timeout: 3s
      retries: 10

  # Serveur Zabbix v7.4.11
  zabbix-server:
    image: zabbix/zabbix-server-mysql:alpine-7.4.11
    container_name: zabbix-server
    restart: always
    user: root
    entrypoint: >
      sh -c "apk add --no-cache curl jq && exec /usr/bin/docker-entrypoint.sh /usr/sbin/zabbix_server -f"
    ports:
      - "10051:10051"
    volumes:
      - ./Scripts:/var/lib/zabbix/externalscripts
      - ./zabbix_export:/var/lib/zabbix/export
    environment:
      DB_SERVER_HOST: zabbix-db
      MYSQL_DATABASE: zabbix
      MYSQL_USER: zabbix
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      TZ: Europe/Paris
    depends_on:
      zabbix-db:
        condition: service_healthy

  # Interface Web Zabbix v7.4
  zabbix-web:
    image: zabbix/zabbix-web-nginx-mysql:alpine-7.4.11
    container_name: zabbix-web
    restart: always
#    expose:
#      - "8080"
    ports:
      - "8080:8080"
    environment:
      ZBX_SERVER_HOST: zabbix-server
      DB_SERVER_HOST: zabbix-db
      MYSQL_DATABASE: zabbix
      MYSQL_USER: zabbix
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      PHP_TZ: Europe/Paris
      ZBX_SERVER_NAME: Zabbix server
    depends_on:
      zabbix-db:
        condition: service_healthy
      zabbix-server:
        condition: service_started

  zabbix-agent:
    image: zabbix/zabbix-agent2:alpine-7.4.11
    container_name: zabbix-agent
    restart: always
    privileged: true
    pid: "host"
    ports:
      - "10050:10050"
    volumes:
      - /:/host:ro
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
    environment:
      ZBX_HOSTNAME: "Zabbix server"
      ZBX_PASSIVESERVERS: "127.0.0.1"
      TZ: "Europe/Paris"
    links:
      - zabbix-server
```

5. Création des dossiers "**`volumes`**"
```bash
mkdir -p mysql_data
mkdir -p Scripts
mkdir -p zabbix_export
```
> Ces dossiers permettent de stocker les données de zabbix, ce qui évite la `réinitialisation` si les conteneurs sont relancés.

---

## 3. Mise en place HTTPS + redirection HTTP -> HTTPS
(certificat déjà généré)

## 1. Installation et modules Apache
* **Installation apache 2 et démarrage au lancement**
    * `apt install apache2`
    * `systemctl enable apache2`

* **Activation des modules pour utiliser le reverse proxy**
    * `a2enmod proxy proxy_http ssl headers`
    * `systemctl restart apache2`

## 2. Création et activation du site
* **Création du site en fichier `.conf`**
    * `nano /etc/apache2/sites-available/zabbix.conf`

* **Activation du site**
    * `a2ensite zabbix.conf`
    * `systemctl reload apache2`

* **Désactiver la page par défaut (la 80)**
    * *(Default) Pour éviter conflit avec docker et graylog*
    * `a2dissite 000-default.conf`
    * `systemctl reload apache2`

* **Vérification**
    * Configuration finie, tester le site en 80 pour la redirection
    * puis en 443 pour voir s'il fonctionne

## 3. Exemple de Configuration (Reverse Proxy)

* **Schéma :** `nom du site` -> `Contenu` -> `backend`

### Fichier zabbix.conf

# Redirection de HTTP (80) vers HTTPS (443)
```apache
<VirtualHost *:80>
    ServerName {FQDN-Serveur}
    Redirect permanent / https://{FQDN-Serveur}/
</VirtualHost>

<VirtualHost *:443>
    ServerName {FQDN-Serveur}

    SSLEngine On
    SSLCertificateFile {lien_vers_certificat.cer}
    SSLCertificateKeyFile {lien_vers_clé_privée.key}

    # Configuration du Proxy
    ProxyRequests Off
    <Proxy *>
        Order deny,allow
        Allow from all
    </Proxy>

    # Points d'entrée Zabbix
    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:8080/
    ProxyPassReverse / http://127.0.0.1:8080/

    # Header indispensable pour que Zabbix sache qu'il est derrière un proxy HTTPS
    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Zabbix-Server-URL "https://{FQDN-Serveur}/"
</VirtualHost>
```
