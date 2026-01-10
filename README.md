# Pharos

A portable offline knowledge lighthouse. A lightweight Raspberry Pi Zero W hotspot powered by Kiwix to deliver Wikipedia and digital libraries to areas without internet connectivity—bringing the Great Library of Alexandria to the palm of your hand.

## About the Name

**Pharos** was the famous lighthouse of Alexandria, one of the Seven Wonders of the Ancient World, built to guide ships safely to harbor. Just as the original Pharos illuminated the path for seafarers, this project serves as a beacon of knowledge, illuminating minds in connectivity-challenged regions by providing offline access to humanity's collective knowledge through Wikipedia and other digital libraries.

## Overview

Pharos transforms a Raspberry Pi Zero 2 W into a self-contained wireless access point that serves offline content via Kiwix. Connect to the hotspot, open your browser, and access Wikipedia, technical documentation, and educational resources—all without an internet connection.

### Key Features

- **Portable & Battery-Friendly**: Designed for the Raspberry Pi Zero W with minimal power consumption
- **Offline-First**: Complete offline access to Wikipedia and other ZIM-based libraries
- **Easy Setup**: Automated installation script handles everything
- **Expandable**: Add more content libraries (ZIM files) as needed
- **Hotspot-Ready**: Built-in wireless access point configuration

## Prerequisites

To clone and use this repository, you'll need:

- **Git** installed on your system
- A **Raspberry Pi Zero W** (or compatible model) running Debian/Raspberry Pi OS
- An **SD card** (512GB recommended) with the OS installed
- **Root access** (the setup script must be run with `sudo`)

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/buguno/pharos
cd pharos
```

### 2. Run the Setup Script

```bash
sudo ./setup.sh
```

The script will:

1. **Update package lists** (`apt update`)
2. **Install required packages**:
   - `kiwix-tools` (provides the `kiwix-serve` binary)
   - `ca-certificates` (for secure HTTPS downloads)
   - `curl` (installed on-demand if needed for ZIM downloads)
3. **Create the ZIM directory** at `/srv/kiwix/content` (configurable via `ZIM_DIR` environment variable)
4. **Set up systemd service** (`kiwix-serve.service`) for automatic startup and management
5. **Prompt for optional ZIM downloads**:
   - Bitcoin wiki ZIM (`bitcoin_en_all_maxi_2021-03.zim`)
   - iFixit ZIM (`ifixit_en_all_2025-12.zim`)
6. **Start the Kiwix service** if ZIM files are present

### 3. Configure Options (Optional)

You can customize the setup using environment variables:

```bash
sudo KIWIX_PORT=8080 ZIM_DIR=/mnt/storage/kiwix ./setup.sh
```

- `KIWIX_PORT`: Port for the Kiwix web server (default: `8080`)
- `ZIM_DIR`: Directory where ZIM files are stored (default: `/srv/kiwix/content`)

## How It Works

### Architecture

```bash
┌─────────────────────────────────────┐
│     Raspberry Pi Zero W             │
│                                     │
│  ┌───────────────────────────────┐  │
│  │  Kiwix Server (Port 8080)     │  │
│  │  Serving ZIM files            │  │
│  └───────────────────────────────┘  │
│           ▲                         │
│           │                         │
│  ┌───────────────────────────────┐  │
│  │  Hotspot (Wi-Fi AP)           │  │
│  │  SSID: PHAROS                 │  │
│  └───────────────────────────────┘  │
│           │                         │
└───────────┼─────────────────────────┘
            │
            ▼
    ┌───────────────┐
    │   Client      │
    │  (Phone/PC)   │
    └───────────────┘
```

### Components

1. **Kiwix Server** (`kiwix-serve`): Serves offline content from ZIM files via HTTP
2. **Systemd Service**: Manages the Kiwix process, ensures it starts on boot, and handles restarts
3. **ZIM Files**: Compressed archive format containing offline Wikipedia/digital library content
4. **Hotspot** (future): Wireless access point configuration (to be implemented)

### Service Management

The Kiwix server runs as a systemd service:

```bash
# Check status
sudo systemctl status kiwix-serve.service

# View logs
sudo journalctl -u kiwix-serve.service -f

# Restart service
sudo systemctl restart kiwix-serve.service

# Stop service
sudo systemctl stop kiwix-serve.service
```

### Accessing Content

Once the service is running, connect to the hotspot and navigate to:

```bash
http://10.42.0.1:8080
```

Or, if accessing from the Pi itself:

```bash
http://localhost:8080
```

## Adding More Content

### Download ZIM Files

You can download additional ZIM files from the [Kiwix ZIM library](https://download.kiwix.org/zim/):

1. Download the `.zim` file to your computer
2. Transfer it to the Pi (via `scp`, USB drive, or other method)
3. Place it in the ZIM directory (default: `/srv/kiwix/content`)
4. Restart the service:

```bash
sudo systemctl restart kiwix-serve.service
```

### Available ZIM Libraries

Popular ZIM files include:

- **Wikipedia** (various languages and sizes)
- **Wikibooks**, **Wiktionary**, **Wikiquote**
- **Project Gutenberg** (free e-books)
- **Stack Overflow** (programming Q&A)
- **Khan Academy** (educational content)
- And many more at [download.kiwix.org](https://download.kiwix.org/zim/)

## Troubleshooting

### Service Not Starting

If `kiwix-serve.service` fails to start:

1. Check if ZIM files exist:

   ```bash
   sudo ls -lah /srv/kiwix/content
   ```

2. Check service logs:

   ```bash
   sudo journalctl -u kiwix-serve.service -n 50 --no-pager
   ```

3. Test the kiwix-serve command manually:

   ```bash
   sudo /usr/bin/kiwix-serve -p 8080 /srv/kiwix/content/*.zim
   ```

4. Verify the service configuration:

   ```bash
   sudo systemctl cat kiwix-serve.service
   sudo cat /etc/default/kiwix-serve
   ```

### No ZIM Files Found

The service will not start if no `.zim` files are present. Download at least one ZIM file using the setup script prompts or manually.

### Port Already in Use

If port `8080` is already in use, set a different port:

```bash
sudo KIWIX_PORT=9090 ./setup.sh
```

## Future Enhancements

- [ ] Hotspot/access point configuration (internal Wi-Fi + USB dongle for WAN)
- [ ] Web-based management interface
- [ ] Automatic ZIM updates
- [ ] Support for multiple languages
- [ ] Battery monitoring and power management
- [ ] Docker containerization option

## License

Licensed under the MIT License. See [`LICENSE`](LICENSE) for more details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgments

- [Kiwix](https://www.kiwix.org/) for the offline content serving technology
- Wikipedia and all content contributors for making knowledge freely available
- The Raspberry Pi Foundation for affordable computing hardware

---

**Light the way. Share knowledge. Build bridges.**
