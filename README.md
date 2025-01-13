# Domain List Update on Router

This repository contains scripts to update the domain list on a router. The scripts are written in Bash and PowerShell, providing SSH connection to the router, merging domain lists from a local file, removing duplicates and lines starting with the `#` symbol, and reloading the `homeproxy` service.

[Перевод на русский](docs/README_ru.md)
## Description

The scripts perform the following actions:
1. Connect to the router via SSH.
2. Read the current domain list from the router.
3. Merge it with data from a local file.
4. Remove duplicate entries, empty lines, and lines starting with the `#` symbol.
5. If a line in the local file starts with `#` followed by a domain, this domain is removed from the resulting list.
6. Copy the updated domain list back to the router.
7. Execute the command to reload the `homeproxy` service on the router.


Additionally, you can use the following command on the router to merge two domain lists without duplicates, replacing the first list with the result:
```bash
sort -u file1.txt file2.txt > tmp.txt && mv tmp.txt file1.txt
```

## Requirements

- SSH access to the router
- Configuration file `.env`
- Bash (for Unix-like systems) or PowerShell (for Windows)

## Setup

### 1. Create a `.env` File

Create a `.env` file in the root directory of the repository with the following variables. You can use the `.env.example` file provided in the repository as a template.

```env
ROUTER_HOST=your_router_ip_address
ROUTER_USER=your_username
SSH_KEY_PATH=~/.ssh/id_rsa
DOMAINS_FILE_PATH=/path/to/domain_file_on_router
LOCAL_DOMAINS_FILE=path/to/local_domains_file.txt
RELOAD_COMMAND="/etc/init.d/homeproxy reload"
REMOVE_DOMAINS_FILE_PATH=/path/to/remove_domain_file_on_router # Path to the file with domains to remove on the router
LOCAL_REMOVE_DOMAINS_FILE=path/to/local_remove_domains_file.txt # Path to the local file with domains to remove
```

### 2. Install Dependencies

Ensure that you have the necessary tools for working with SSH installed on your system.

### 3. Running the Scripts

#### Bash

1. Make sure you have Bash installed (it is typically pre-installed on most UNIX systems like Linux and macOS).
2. Save the Bash script to a file, e.g., `update_domains.sh`.
3. Make the file executable:
   ```bash
   chmod +x update_domains.sh
   ```
4. Run the script:
   ```bash
   ./update_domains.sh
   ```

#### PowerShell

1. Ensure you have PowerShell installed. It is pre-installed on Windows, and available for installation on other operating systems.
2. Save the PowerShell script to a file, e.g., `update_domains.ps1`.
3. Open PowerShell.
4. Navigate to the directory where the script file is located:
   ```powershell
   cd path/to/directory
   ```
5. Run the script:
   ```powershell
   .\update_domains.ps1
   ```

## Note

If you encounter errors when running the scripts, check for the presence of the `.env` file and verify that the values are correct. Ensure you have access permissions to the SSH key and can connect to the router via SSH.

## Contribution

We welcome your suggestions and improvements! Please create a `pull request` or open an `issue` for discussion.

## License

This project is licensed under the MIT License. See the LICENSE file for details.
