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
2.  Récupérer les images Docker (Zabbix 7.4.11 MySQL 9.6.0) :
    ```bash
    docker pull zabbix/zabbix-agent2:alpine-7.4.11
    docker pull zabbix/zabbix-web-nginx-mysql:alpine-7.4.11
    docker pull zabbix/zabbix-server-mysql:alpine-7.4.11
    docker pull mysql:9.6.0
    ```
3. Créer le fichier `.env`

```bash
MYSQL_PASSWORD="mysqlpassword"
MYSQL_ROOT_PASSWORD="mysqlrootpassword"
```

4. Créer le fichier `docker-compose.yml` complet.

```yaml
services:
  # Base de données MySQL 9.6.0
  zabbix-db:
    image: mysql:9.6.0
    container_name: zabbix-db
    restart: always
    command: >
      --character-set-server=utf8mb4
      --collation-server=utf8mb4_bin
      --log-bin-trust-function-creators=1
      --innodb_buffer_pool_size=1G
      --skip-name-resolve
    volumes:
      - ./mysql_data:/var/lib/mysql
    environment:
      MYSQL_DATABASE: zabbix
      MYSQL_USER: zabbix
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-p${MYSQL_ROOT_PASSWORD}"]
      interval: 15s
      timeout: 3s
      retries: 10

  # Serveur Zabbix v7.4.11
  zabbix-server:
    image: zabbix/zabbix-server-mysql:alpine-7.4.11
    container_name: zabbix-server
    restart: always
    user: root
    entrypoint: >
      sh -c "apk add --no-cache curl jq ca-certificates && update-ca-certificates && exec /usr/bin/docker-entrypoint.sh /usr/sbin/zabbix_server -f"
    ports:
      - "10051:10051"
    volumes:
      - ./Scripts:/var/lib/zabbix/externalscripts
      - ./zabbix_export:/var/lib/zabbix/export
      - /etc/ssl/private/ROOTCA.cer:/usr/local/share/ca-certificates/ROOTCA.crt:ro
    environment:
      DB_SERVER_HOST: zabbix-db
      MYSQL_DATABASE: zabbix
      MYSQL_USER: zabbix
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      TZ: Europe/Paris
      ZBX_CACHESIZE: "256M"
      ZBX_STARTVMWARECOLLECTORS: 10
      ZBX_STARTPINGERS: 5
    depends_on:
      zabbix-db:
        condition: service_healthy

  # Interface Web Zabbix v7.4
  zabbix-web:
    image: zabbix/zabbix-web-nginx-mysql:alpine-7.4.11
    container_name: zabbix-web
    restart: always
    dns:
      - 10.100.50.45
      - 10.100.50.46
    dns_search:
      - cgo.local
    ports:
      - "8080:8080"
    volumes:
      - ./zabbix_config/ldap.conf:/etc/openldap/ldap.conf:ro
      - /etc/ssl/private/ROOTCA.cer:/etc/ssl/certs/ROOTCA.cer:ro
    environment:
      ZBX_SERVER_HOST: zabbix-server
      DB_SERVER_HOST: zabbix-db
      MYSQL_DATABASE: zabbix
      MYSQL_USER: zabbix
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      PHP_TZ: Europe/Paris
      ZBX_SERVER_NAME: SVPL01-ZABBIX-03
      WEB_REAL_IP_FROM: "172.16.0.0/12"
      WEB_REAL_IP_HEADER: "X-Forwarded-For"
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
    user: root
    entrypoint: >
      sh -c "apk add --no-cache ca-certificates && update-ca-certificates && exec /usr/bin/docker-entrypoint.sh /usr/sbin/zabbix_agent2 -f"
    ports:
      - "10050:10050"
    volumes:
      - /:/host:ro
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /etc/ssl/private/ROOTCA.cer:/usr/local/share/ca-certificates/ROOTCA.crt:ro
    environment:
      ZBX_HOSTNAME: "Zabbix server"
      ZBX_PASSIVESERVERS: "127.0.0.1,172.16.0.0/12"
      TZ: "Europe/Paris"
    links:
      - zabbix-server
```

5. Création des dossiers "**`volumes`**"
```bash
mkdir -p mysql_data
mkdir -p Scripts
mkdir -p zabbix_export
mkdir -p zabbix_config
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
    ServerName SVPL01-ZABBIX-03.cgo.local
    Redirect permanent / https://SVPL01-ZABBIX-03.cgo.local/
</VirtualHost>

<VirtualHost *:443>
    ServerName SVPL01-ZABBIX-03.cgo.local

    SSLEngine On
    SSLCertificateFile /etc/ssl/private/SVPL01-ZABBIX-03.cer
    SSLCertificateKeyFile /etc/ssl/private/SVPL01-ZABBIX-03.key

    # Configuration du Proxy
    ProxyRequests Off
    <Proxy *>
        Require all granted
    </Proxy>

    # Points d'entrée Zabbix
    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:8080/
    ProxyPassReverse / http://127.0.0.1:8080/
    # En-têtes pour le proxying
    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-Port "443"
    # Transmet l'adresse IP réelle de la machine cliente :
    ProxyAddHeaders On
    RequestHeader set X-Zabbix-Server-URL "https://SVPL01-ZABBIX-03.cgo.local/"
</VirtualHost>
```

# Migration de données entre Zabbix 6.0 et Zabbix 7.4.11

## 1. Dump de l'ancienne base de données

Pour commencer la migration de données entre les deux zabbix, un dump de la base est nécessaire. Pour se faire, on va utiliser un outil fournit directement par MySQL nommé mysqldump.

```bash
mysqldump -u {user_mysql} -p --single-transaction --routines --triggers {nom_bdd} > /tmp/zabbix_dump_{date}.sql
```

Après le dump réalisé, il va maintenant falloir le transférer sur le nouveau serveur.

## 2. Transfert du dump sur le nouveau Zabbix

Maintenant que le dump est effectué, on procède au transfert de celui-ci sur le nouveau serveur. Pour se faire, rien de bien compliqué, on va effectuer un "scp" donc une copie via le service SSH sur le serveur distant.

```bash
scp /tmp/zabbix_dump_{date}.sql {user_distant}@{IP_New_Zabbix}:/opt/zabbix/zabbix_export
```

Maintenant notre dump sur le nouveau serveur, on va passer à l'import dans le conteneur MySQL qui servira de base de données pour notre serveur Zabbix.

## 3. Import de la base dans le conteneur MySQL

Afin d'importer notre base dans MySQL sans problème, on doit réaliser deux grandes étapes **NÉCESSAIRES**.

### 3.1 Mise en place du dossier pour les données MySQL

Pour éviter tout problème de stockage, on va séparer les données MySQL dans un dossier précis nous permettant d'initialiser la nouvelle base de données en intégrant les informations du dump.

On va donc créer un dossier nommé `mysql_data`, si bien sûr il n'est pas encore créé.

```bash
mkdir -p /opt/zabbix/mysql_data
```

### 3.2 Mise en place du docker-compose.yml

Maintenant que le dossier pour les données est créé, on va mettre en place un nouveau `docker-compose.yml` le temps d'importer les données sur le conteneur MySQL.

Ce fichier sera uniquement constitué du services MySQL, n'ayant pas besoin du reste pour importer la base sous peine d'avoir des conflits.

fichier `docker-compose.yml` : 

```bash

services:
  # Base de données MySQL 9.6.0
  zabbix-db:
    image: mysql:9.6.0
    container_name: zabbix-db
    restart: always
    command: >
      --character-set-server=utf8mb4
      --collation-server=utf8mb4_bin
      --log-bin-trust-function-creators=1
      --innodb_buffer_pool_size=4G
      --innodb_redo_log_capacity=2G
      --innodb_flush_log_at_trx_commit=0
      --innodb_doublewrite=0
      --max_allowed_packet=512M
      --skip-name-resolve
    volumes:
      - ./mysql_data:/var/lib/mysql
      - /opt/zabbix/zabbix_export/zabbix_dump_20260901.sql:/docker-entrypoint-initdb.d/init_zabbix.sql:ro
    environment:
      MYSQL_DATABASE: zabbix
      MYSQL_USER: zabbix
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      TZ: Europe/Paris
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-p${MYSQL_ROOT_PASSWORD}"]
      interval: 15s
      timeout: 5s
      retries: 20
      start_period: 7200s # laisse mysql intégrer les données tranquillement

```

Toute cette partie : 

`- /opt/zabbix/zabbix_export/zabbix_dump_{date}.sql:/docker-entrypoint-initdb.d/init_zabbix.sql:ro`

Va permettre de mapper le fichier de dump sur le conteneur, et à cet endroit précis, l'import de la base va se faire automatiquement sans aucune action.
On peut enfin lancer le conteneur et suivre les logs pour voir où en est l'import et savoir faire de patience.

## 4. Mise à jour automatique de la base de données Zabbix

Étant donné que la base actuelle date de la version 6.0 de Zabbix, il faut potentiellement mettre à jour le format de la base, et son contenu.

Heureusement, Zabbix a prévu le coup avec un outil automatique qui consulte la base de données et la met à jour d'elle même, nous évitant de le faire et d'avoir de potentielles erreurs.

Pour celà, rien de bien compliqué, lancer les conteneurs ! Et suivre les logs de mise à jour de base !

Il faut juste utiliser de nouveau le fichier `docker-compose.yml` de base avec chacun des services.

```bash
docker compose up -d
```

Le serveur Zabbix est maintenant en marche !

# Mise en place connexion LDAPS sur Zabbix

## 1. Configuration du LDAPS

### 1.1 Préparation des certificats de l'autorité (CA)
1. Récupérer les certificats au format Base64 (PEM) de la **Root CA** et de l'autorité intermédiaire (**SUBCA**).

2. Concaténer les deux certificats dans un fichier unique :
   ```bash
   cat CA.crt SUBCA.crt > /etc/ssl/private/ROOTCA.cer
   ```

### 1.2 Création du fichier ldap.conf
1. Créer le fichier de configuration OpenLDAP local :
   ```bash
   nano /opt/zabbix/zabbix_config/ldap.conf
   ```
2. Insérer la configuration suivante :
   ```text
   TLS_CACERT /etc/ssl/certs/ROOTCA.cet
   TLS_REQCERT demand
   ```

### 1.3 Montage dans le docker-compose.yml
Ajouter les montages des certificats et de la configuration dans la section `volumes` du service `zabbix-web` :

### 1.4 Validation et test
1. Dans l'interface Zabbix, se rendre dans **Users** > **Authentication** > **LDAP settings**.
2. Configurer le serveur LDAP :
   * **Name :** `LDAPS Server`
   * **Host :** `ldaps://{nom_DNS_du_serveur_AD}`
   * **Port :** `636`
   * **Base DN :** `OU={OU_value},DC={domain},DC={domain}`
   * **Search attribute :** `sAMAccountName`
   * **Bind DN :** `CN={compte_service},OU={OU_compte_service},DC={domaine},DC={extension}`
   * **Bind password :** `{mdp_compte_service}`
3. Cliquer sur **Test** pour valider la communication LDAPS chiffrée.
4. Une fois le test réussi, activer l'authentification LDAP par défaut.

# Problématiques lors de la migration de Zabbix 
