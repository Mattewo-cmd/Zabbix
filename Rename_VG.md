# Renommer un Volume Group (VG) LVM sur Debian

Cette documentation décrit la procédure technique pour changer le nom d'un Groupe de Volumes (Volume Group - VG) sous Debian. (Version 13.1)

> [!WARNING]
> **Avertissement Critique**
> * **Sauvegardez vos données** avant toute manipulation sur les partitions.
> * Cette procédure est décrite pour un VG de données. Si vous renommez le VG contenant la racine (`/`), voir la section **"Cas Particulier"** en bas de document.

## 1. Identification

Avant de commencer, listez les VGs pour récupérer le nom exact actuel.

```bash
vgs
```

Sortie exemple :
```text
  VG        #PV #LV #SN Attr   VSize    VFree
  vg_ancien   1   2   0 wz--n- 500.00g  10.00g
```

## 2. Renommage du Volume Group

La commande `vgrename` prend en paramètre l'ancien nom puis le nouveau nom.

Syntaxe :
```bash
vgrename <ancien_nom> <nouveau_nom>
```

Exemple :
```bash
vgrename vg_ancien vg_nouveau
```

Si succès :
> Volume group "vg_ancien" successfully renamed to "vg_nouveau"

## 3. Mise à jour de la configuration système

Une fois le VG renommé, le système ne pourra plus monter les partitions automatiquement si les fichiers de configuration ne sont pas mis à jour. Pour cela il faut mettre à jour les fichiers de configuration (`/etc/fstab`, `/boot/grub/grub.cfg`, `/etc/initramfs-tools/conf.d/*`).

```bash
sed -i 's/{ancien_nom_vg}/{nouveau_nom_vg}/g' /etc/fstab
sed -i 's/{ancien_nom_vg}/{nouveau_nom_vg}/g' /etc/initramfs-tools/conf.d/*
sed -i 's/{ancien_nom_vg}/{nouveau_nom_vg}/g' /boot/grub/grub.cfg
```

## 4. Prise en compte au démarrage (Initramfs & Grub)

Même si le VG ne contient pas le système racine, il est recommandé de mettre à jour l'environnement de démarrage pour éviter des délais d'attente ou des erreurs lors du boot.

1. Mettre à jour l'image Initramfs :
```bash
update-initramfs -u -k all
```

2. Mettre à jour le chargeur Grub :
```bash
update-grub
```

3. Relancer le daemon :
```bash
systemctl daemon-reload
```

## 5. Vérification

Vérifiez que le changement est bien pris en compte par le noyau LVM :

```bash
lvs
```

Si tout est correct, un redémarrage est conseillé pour valider le montage automatique :

```bash
systemctl reboot
```

---

## 🚨 Cas Particulier : Renommer le VG Racine (Root)

Si le VG à renommer contient le système d'exploitation (/) :

* **NE PAS** effectuer la procédure depuis le système en cours d'exécution.
* Démarrez sur une **Live USB** (Debian Live) ou alors en Recovery Mode.
* Ouvrez un terminal et faites le `vgrename`.

Montez le système en mode **chroot** (`/mnt/systeme`).

```bash
# Créez un point de montage temporaire
sudo mkdir /mnt/systeme

# Montez votre LV racine (ex: "root")
mount /dev/{nom_nouveau_vg}/root /mnt/systeme

# Montez les autres partitions si elles existent (ex: /boot)
mount /dev/{partition_boot} /mnt/systeme/boot #exemple partition_boot 'sda1'

# "Chrootez" dans votre système
mount --bind /dev /mnt/systeme/dev
mount --bind /proc /mnt/systeme/proc
mount --bind /sys /mnt/systeme/sys
chroot /mnt/systeme
mkdir /var/tmp
```

Effectuez les modifications **Partie 3 et 4** de la documentation.

Vérifier :
```bash
grep {nouveau_nom_vg} /etc/fstab 
ls /dev/mapper/ #le nouveau_nom_vg devrait être affiché
```

Sortir du chroot et Supprimer le point de montage temporaire :
```bash
exit 
umount /mnt/systeme/dev /mnt/systeme/proc /mnt/systeme/sys /mnt/systeme/boot 
umount /mnt 
reboot
```

**Redémarrer**
Voir si le redémarrage se fait bien, sinon revenir au snapshot précédent.