# PowerShell Container Script

### Easily manage Dynamics 365 (NAV/BC) Docker containers

**PSCS** allows you to easily create/update/manage Dynamics 365 (NAV/BC) Docker containers via Microsoft PowerShell using the [NAVContainerHelper](https://github.com/Microsoft/navcontainerhelper)

## How to use?

Simply run _PSCS.ps1_ in PowerShell. The script will automatically elevate itself if you're not running it as an Administrator.

After the _installation of all necessary modules_ you can choose between the following menu options:

### create a new template

This option allows you to create new templates to create containers from. Upon choosing this option you will be asked for any parameters necessary which are:

- Prefix (used for container creation)
- Name
- Image
- License File (file dialog can simply be closed to use CRONUS license)

### create a new container

Based on a template you can create new Docker containers for your NAV/BC databases. The container name is based on the prefix set in the template and a name you enter when choosing this option.

Example for prefix BC365:

- BC365-TEST
- BC365-DEV

### update license

Allows you to upload a license file to any running container.

### remove an existing container

Shows all running containers (fitting into the name scheme `PREFIX-NAME`) allowing you to choose one and delete it.


