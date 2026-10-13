# VNPT Smartbox 2 (S805) – Debian / Armbian on Android Kernel

## Short Introduction


<img width="872" height="533" alt="image" src="https://github.com/user-attachments/assets/23acff37-f67f-409d-85da-86decca165c5" />
---

This project provides a **Debian / Armbian (Bullseye)** system for the **VNPT MyTV Smartbox 2** powered by **Amlogic S805 (Meson8b)**.  
Due to secure-boot restrictions on some boards, this setup **reuses the stock Android kernel (3.10.33)** and boots Debian via a custom initramfs and root filesystem.

The result is a **fully functional Armbian-like Debian 11 system using sysvinit**, suitable for real-world server workloads while remaining compatible with both secure and non-secure devices.

This project focuses on:
- Maximum compatibility with vendor bootloaders
- No need to unlock or replace U-Boot
- Safe installation to eMMC
- Easy rollback to Android if needed

---
## Installation Instructions

Download the releases here: https://github.com/chieunhatnang/vnptsmb2-s805-debian/releases

There are **two supported installation methods**. The difference is where the Debian root filesystem is stored:

- **Internal eMMC rootfs**: Recommended if the internal storage is large enough. This uses the existing hardware and usually gives better I/O speed.
- **SD card rootfs**: Recommended if you need a larger root filesystem. The box still uses the internal boot environment, but Debian runs from the SD card.

Please follow the steps **exactly**. No information in this guide is optional unless explicitly stated.





---



---

### 1. Extract the Files

- Use **7z (7-Zip)** to extract all provided archives.

---

### 2. Prepare the SD Card (Debian Image)

Skip this step if you want to boot Debian fully from **internal eMMC**.

- Take the file:

  **`VNPTSMB2-S805-Debian-Bullseye-2.0.img`**

- Use **Balena Etcher** to burn this image to an **SD card**.
- Use this SD card only for the **SD card rootfs** installation method.

---

### 3. Prepare the USB Drive (TWRP Files)

- Take the archive:

  **`TWRP-VNPTSMB2-Debian-Bullseye-2.0.7z`**

- After extracting, you will see **two items**:
  - `twrp-3.1.1.zip`
  - `TWRP` (folder)

- Copy **both** `twrp-3.1.1.zip` **and** the `TWRP` folder to a **USB drive**.


---

Chú Ý quan trọng, để đúng định dạng và vị trí file, lệch vị trí folder thôi là TWRP sẽ không nhìn thấy file để nạp!



SD Cards:
/sdcard/TWRP/BACKUPS/ ...etc

USB Drive (Make Sure It In FAT32 Format)

/[Usb Drive Name ]/TWRP/BACKUPS/ ... etc





---

### 4. Load TWRP Using Stock Recovery

> Replacing the stock recovery is **impossible** on this device.  
> TWRP is loaded as an **application**, not flashed permanently.

Steps:

1. Press and hold the **reset key**
2. Plug in the **power cable**
3. When **stock recovery** appears:
   - Select **“Apply update from Udisk”**
   - Select **`twrp-3.1.1.zip`**

TWRP 3.1.1 will now be loaded as an application.

---

### 5. Restore Debian in TWRP

Once TWRP is loaded:

1. Select **`Restore`**
2. Select **`Select Storage`**
3. Choose the **Debian 11 backup** to restore

You will see **four partitions** available for restore:

Choose the restore partitions based on the installation method you want:

#### Method A: Rootfs on internal eMMC

Use this method for the best I/O speed and the simplest setup.

- Restore **`env`**, **`data`**, and **`cache`**.
- Restore **`boot`** only if your device does not boot after trying without it.
- No Debian SD card image is required.
- Debian rootfs will be installed on the internal **`data`** partition and booted from **`/dev/data`**.

#### Method B: Rootfs on SD card

Use this method if you need a larger Debian root filesystem than the internal storage can provide.

- First complete **Step 2** and insert the prepared SD card.
- Restore **`env`** only.
- Optionally restore **`cache`** if you want TWRP to be available later from stock recovery.
- Do **not** restore **`data`** unless you also want to overwrite the internal Android data partition with the Debian rootfs.
- Debian rootfs will be loaded from **partition 2 of the SD card**: **`/dev/mmcblk0p2`**.

---

#### Partition: `boot`

- Android boot partition that contains the kernel
- You **can deselect this partition** to try first

---

#### Partition: `env`

- U-Boot environment partition
- It contains **custom code** to support booting from **SD card** and **internal eMMC**

**Boot behavior after installing this partition:**

- After installing this partition, the box will boot from **internal eMMC** (`/dev/data`) by default.
- When an SD card is plugged in, it will boot from **partition 2 of the SD card** (`/dev/mmcblk0p2`).
- For an SD card rootfs install, this is the only required TWRP partition to restore.

---

#### Partition: `data`

- Debian **root filesystem**
- Restore this partition only for the **internal eMMC rootfs** installation method.
- Debian will be installed and run from this partition as **`/dev/data`**.

---

#### Partition: `cache`

- `twrp-3.1.1.zip` will be copied here
- After installing, you can load TWRP again by:
  - Entering stock recovery
  - Selecting **“Apply update from cache”**
  - Selecting **`twrp-3.1.1.zip`**

Chú Ý quan trọng, để đúng định dạng và vị trí file, lệch vị trí folder thôi là TWRP sẽ không nhìn thấy file để nạp


---

### 6. First Boot and SSH Login

After restoring Debian and rebooting the box:

1. Plug the box's **Ethernet port** into your router.
2. Find the box's IP address from your router's DHCP client list.
3. Connect by SSH:

   ```sh
   ssh root@<box-ip-address>
   ```

4. Log in with the default credentials:
   - Username: **`root`**
   - Password: **`1234`**

On the first login, Debian will ask you to change the root password.

> No HDMI output is expected. Use Ethernet and SSH for first boot access.

---

### 7. Final Notes

- This setup allows flexible booting between **internal eMMC** and **SD card**
- TWRP remains available as an application via the cache mechanism
- No permanent modification to stock recovery is required or possible
- Boot priority is controlled entirely by the `env` partition logic

### Restore Back to Android (Important)

If you want to **return to Android**, simply flash the following ROM via TWRP:
https://github.com/chieunhatnang/vnptsmb2-s805-debian/releases/download/vnptsmb2-s805-buster-3.10.33-2025.12/Android-ATV4-TWRP.zip

This will restore a clean Android ATV environment and overwrite the Debian setup safely.

---

## What Can You Do With It?

Despite running on an Android kernel and sysvninit, the system behaves like a normal Debian server and can be used for:

- LEMP stack (Nginx, MariaDB/MySQL, PHP)
- Node.js 18 (APIs, bots, background services)
- OpenVPN / WireGuard-Go
- Pi-hole (DNS filtering & ad blocking)
- FTP / SFTP server
- Transmission (torrent box)
- SSH remote management
- LAN file server / lightweight NAS
- Cron jobs, monitoring, and automation

Just remember : No systemd. Use `service xxx reload|start|stop|restart` instead of `systemd start|stop|restart xxx`.
---

## Further Reading & Technical Details

For deep technical explanations, boot flow analysis, secure-boot limitations, partition layout, and design decisions, please refer to the blog post:

**Using Android kernel to load Debian on VNPT MyTV Smartbox 2 (S805)**  
https://chieunhatnang.de/p/using-android-kernel-to-load-debian-on-vnpt-mytv-smartbox-2-s805/

This blog documents the full journey, including experiments, pitfalls, and rationale behind the final approach used in this repository.

---

## Disclaimer

This project is intended for **advanced users**.  
Flashing firmware always carries a risk. You are responsible for your own hardware.



