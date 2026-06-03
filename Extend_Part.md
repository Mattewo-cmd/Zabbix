# Extension à chaud du disque principal LVM

Cette procédure s'applique lorsque l'on souhaite étendre un disque principal (ex: `/dev/sda`) dont l'espace a été agrandi côté hyperviseur (VMware), en créant une **nouvelle partition** pour combler l'espace vide, puis en l'ajoutant au Volume Group (VG) existant.

---

## 1. Modification de la table de partition

Lancer l'utilitaire `fdisk` sur le disque concerné :

```bash
fdisk /dev/sda
```

**Exemple de résultat :**
```text
Bienvenue dans fdisk (util-linux 2.23.2).
Les modifications resteront en mémoire jusqu'à écriture.
Soyez prudent avant d'utiliser la commande d'écriture.
```

### A. Vérifier la table actuelle
Dans l'invite de commande `fdisk`, tapez `p` :

```text
Commande (m pour l'aide) : p
```

**Exemple de résultat :**
```text
Disque /dev/sda : 1649.3 Go, 1649267441664 octets, 3221225472 secteurs
...
Périphérique Amorçage Début Fin Blocs Id. Système
/dev/sda1 2048 2946079129 1473038541 8e Linux LVM
```

### B. Créer la nouvelle partition
Tapez `n` (new), puis `p` (primary), acceptez les valeurs par défaut pour le numéro et les secteurs :

```text
Commande (m pour l'aide) : n
...
Sélection (p par défaut) : p
Numéro de partition (2-4, 2 par défaut) : [Entrée]
Premier secteur ... : [Entrée]
Dernier secteur ... : [Entrée]
```

**Exemple de résultat :**
```text
La partition 2 de type Linux et de taille 131,2 GiB est configurée
```

### C. Changer le type en LVM
Tapez `t` (type), sélectionnez la partition (2), et entrez le code `8e` (Linux LVM) :

```text
Commande (m pour l'aide) : t
Numéro de partition (1,2, 2 par défaut) : 2
Code Hexa (taper L pour afficher tous les codes) : 8e
```

**Exemple de résultat :**
```text
Type de partition « Linux » modifié en « Linux LVM »
```

### D. Vérifier et écrire les modifications
Tapez `p` pour vérifier la présence de `sda2`, puis `w` pour écrire et quitter :

```text
Commande (m pour l'aide) : p
...
/dev/sda1 2048 2946079129 1473038541 8e Linux LVM
/dev/sda2 2946080768 3221225471 137572352 8e Linux LVM

Commande (m pour l'aide) : w
```

**Exemple de résultat :**
```text
La table de partitions a été altérée.
Appel d'ioctl() pour relire la table de partitions.
Attention : la table de partitions n'a pas pu être relue...
Synchronisation des disques.
```

---

## 2. Prise en compte par le noyau

Forcez la relecture de la table de partition par le noyau :

```bash
partprobe /dev/sda
```

*(Si nécessaire)* Redimensionner le volume physique existant (si applicable) :
```bash
pvresize /dev/sda1
```
**Résultat :** `1 physical volume(s) resized / 0 physical volume(s) not resized`

---

## 3. Création du Volume Physique (PV)

Initialisez la nouvelle partition en tant que Volume Physique LVM :

```bash
pvcreate /dev/sda2
```

**Exemple de résultat :**
```text
Physical volume "/dev/sda2" successfully created
```

Vérifiez l'état des PVs :
```bash
pvs
```
**Exemple de résultat :**
```text
PV VG Fmt Attr PSize PFree
/dev/sda1 data lvm2 a-- 1,37t 0
/dev/sda2 lvm2 --- 131,20g 131,20g
/dev/sdb2 centos lvm2 a-- 126,51g 4,00m
```

---

## 4. Extension du Groupe de Volumes (VG)

Ajoutez le nouveau PV au VG existant (ici nommé `data`) :

```bash
vgextend data /dev/sda2
```

**Exemple de résultat :**
```text
Volume group "data" successfully extended
```

Vérifiez que l'espace est disponible dans le VG :
```bash
vgs
```
**Exemple de résultat :**
```text
VG #PV #LV #SN Attr VSize VFree
data 2 1 0 wz--n- 1,50t 131,20g
```

---

## 5. Extension du Volume Logique (LV)

Étendez le volume logique (ici `lv_data`) pour utiliser tout l'espace libre ajouté :

```bash
lvextend -l +100%FREE /dev/mapper/{partition-à-agumenter}
```
ou
```bash
lvextend -L +?G /dev/mapper/{partition-à-agumenter}
```

**Exemple de résultat :**
```text
Size of logical volume data/lv_data changed from 1,37 TiB ... to 1,50 TiB ...
Logical volume lv_data successfully resized.
```

---

## 6. Extension du système de fichiers (Filesystem)

Appliquez l'agrandissement sur le système de fichiers (ici XFS) :

```bash
xfs_growfs /dev/mapper/{partition-à-agumenter}
```

Pour le système de fichiers ext4

```bash
resize2fs /dev/mapper/{partition-à-agumenter}
```

**Exemple de résultat :**
```text
meta-data=/dev/mapper/data-lv_data ...
data blocks changed from 368259072 to 402651136
```

---

## 7. Vérification finale

Contrôlez l'espace disque final :

```bash
df -h
```

**Exemple de résultat :**
```text
Sys. de fichiers Taille Utilisé Dispo Uti% Monté sur
...
/dev/mapper/{partition-à-agumenter} 1,5T 1,2T 349G 78% /data
```