# Dell Home Lab Documentation

**Server:** Dell PowerEdge R310 (11th Gen)  
**OS:** Ubuntu 24.04 LTS (Noble Numbat)  
**Primary Purpose:** Docker Host & Synology Backup Target  

---

## 1. Storage Architecture

### Physical Drives
| Disk | Type | Size | Connection | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **nvme0n1** | FireCuda NVMe | 1TB | PCIe Adapter | **Fast Storage:** OS Boot + Docker Images/Containers |
| **sda** | SATA HDD | 3TB | PERC H200/700 | **Bulk Storage:** Backups & ISOs |

### Mount Points & Filesystem
| Path | Device | Filesystem | Description |
| :--- | :--- | :--- | :--- |
| `/` | `/dev/sda3` (LVM) | ext4 | **OS Root.** ~2.6TB available. Used for OS logs/configs. |
| `/mnt/nvme` | `/dev/nvme0n1` | ext4 | **High Speed Data.** Manual mount for Docker data. |
| `/mnt/backups` | `/dev/sda` (Folder) | ext4 | **Bulk Data.** Directory on the 3TB drive for MinIO storage. |

**fstab Configuration (`/etc/fstab`):**
```bash
# NVMe Drive Auto-Mount
UUID=[YOUR-NVME-UUID] /mnt/nvme ext4 defaults 0 2

```

---

## 2. Docker Configuration

**Installation Method:** Official Docker Repository (not Snap/Apt default).

**User Access:** User `ricardo` added to `docker` group (no `sudo` required).

### Custom Storage Location

Docker has been reconfigured to use the NVMe drive for all images and containers to improve performance.

**Config File:** `/etc/docker/daemon.json`

```json
{
  "data-root": "/mnt/nvme/docker-data"
}

```

**Directory Structure:**

* **Service Configs:** `~/docker/{service_name}/` (YAML files live here)
* **Persistent Volumes:** `/mnt/nvme/docker-data/volumes/` (Database files live here automatically)

---

## 3. Services

### A. MinIO (S3 Backup Target)

**Purpose:** Acts as an S3-compatible destination for Synology Hyper Backup.

* **Docker Compose Location:** `~/docker/minio/docker-compose.yml`
* **URL (Console):** `http://[SERVER-IP]:9001`
* **URL (API):** `http://[SERVER-IP]:9000`

**Configuration Strategy:**

* **Application Data:** Stored on **NVMe** (Fast UI/Database).
* **Backup Data:** Bind-mounted to `/mnt/backups` on **SATA** (Bulk Storage).

**Docker Compose File:**

```yaml
services:
  minio:
    image: quay.io/minio/minio:latest
    container_name: minio
    restart: unless-stopped
    ports:
      - "9000:9000" # S3 API Port (Synology connects here)
      - "9001:9001" # Web Console Port (Management)
    environment:
      MINIO_ROOT_USER: "admin"
      MINIO_ROOT_PASSWORD: "[REDACTED]"
    volumes:
      # Config & Metadata (Fast NVMe)
      - minio_config:/root/.minio
      # Actual Data (Slow SATA)
      - /mnt/backups:/data
    command: server /data --console-address ":9001"

volumes:
  minio_config:

```

---

## 4. Synology Integration

**Source:** Synology DSM 7.2 (Hyper Backup)

**Destination:** S3 Storage (Custom URL)

**Settings:**

* **Server Address:** `http://192.168.x.x:9000`
* **Signature Version:** v4
* **Region:** `us-east-1` (Default)
* **Bucket Name:** `synology-backup`

---

## 5. Maintenance Commands

**Check Storage Usage:**

```bash
df -h

```

*(Ensure `/mnt/nvme` is not full)*

**Restart MinIO:**

```bash
cd ~/docker/minio
docker compose restart

```

**View Logs:**

```bash
docker logs -f minio

```

```

```
