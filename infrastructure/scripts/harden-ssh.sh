#!/bin/bash
# P0: Production SSH Hardening - Overwrites authorized_keys
set -euo pipefail

# 1. Define Authorized Keys
SHAHID_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDGTPesV1vHxWK9NgUm+30/NLALXm0qdYNXAGD7QRzSbBBoPFaMW8MX0NhQjVJap+nBSylQDpLwJv2OB4iklz9eoTLsKwSJTrMTCCU775486gEBRlhqKW2B8ZwrNI6zMzt44oW+RLzZstMM9KrO+L+ahKshqxO9hTnqVHPjxTmFs1gXdt83dXeBnmnlaKQ+XJRUjq3FbZX7I6wdwWRWEQrJoIRxiOCepF7GZisTbpGNHiCWEFJL45n+eQ8PBJutR/GxVhwrYYffIkjBFMC3P0WXzxI8088ncWPLGgIvagtC4dSVaFFaSn7Y+YuEH6Bv1/q/hemvKe4+sdRSJf/TK73HyLbKl/ZVgSqrZi8rFcIAO6D6VyjCTABspimBPu7xsmkuDfOD6WcAPhlb5c/gwyaE0bK89r0jQ+1pv3GXYR9pRn4F70GTt9Tyd5nwEkV+oqToL3xb5fuURv4cfoZv0uw1po42fkYUjgxNdrIpkFTYYhoF57crsmLZadVOA5rkxR49crUfshwxFlBhT5xJ1epKRRAppttPzjkXJzzofJDwRytvUmwgAyrOJQgUvdXwwpVbrNXtrIm1N1ADWrAwnaf4My6dLnK7zvHO3SeSnnJM9wGi939kzQOMPfJkKWIcHFgnvCr1W0sv3LI0lk3qzVszOKYYQVvt8aVIULZSkfPm4w== shahid@DESKTOP-L7100KG" 
NIK_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGmRPcgLVaZ8yed2hwxE6q9db9jLqh4m1Yg7WEQqp/k4 nik@Mac"
ROMAN_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEt3T2dkKJzoGY24GgOcJDEtZZoopgSPBE0lZgSfNGJO roman@romandid.xyz"
MOHAMMED_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFO47v2j1U9jVT/GQQTBKRuWVmQmdFSkCIgc7LIJUDeL mohammed@do-droplet"

# 2. Target File
AUTH_KEYS="/root/.ssh/authorized_keys"

# 3. Create Golden List Content
# We use > for the first line to OVERWRITE existing keys, and >> for the rest to append
echo "Restricting access to Nik, Shahid, Roman, and Mohammed..."
echo "$NIK_KEY" > "$AUTH_KEYS"
echo "$SHAHID_KEY" >> "$AUTH_KEYS"
echo "$ROMAN_KEY" >> "$AUTH_KEYS"
echo "$MOHAMMED_KEY" >> "$AUTH_KEYS"

# 4. Strict Permissions
chmod 600 "$AUTH_KEYS"
echo "SSH Lockdown successful."