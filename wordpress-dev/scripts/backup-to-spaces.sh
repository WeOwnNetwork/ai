#!/bin/bash

# Configuration
SITE_NAME=$1
BACKUP_DIR="/tmp/backups"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M)
FILE_NAME="${SITE_NAME}_backup_${TIMESTAMP}.tar.gz"

# 1. Dynamic Container Discovery
DB_CONTAINER=$(docker ps --format '{{.Names}}' | grep db | head -n 1)
APP_CONTAINER=$(docker ps --format '{{.Names}}' | grep wordpress | grep -v db | head -n 1)

# 2. Dynamic Path Discovery
WP_PATH=$(docker inspect --format='{{range .Mounts}}{{.Source}}{{end}}' $APP_CONTAINER 2>/dev/null)
if [ -z "$WP_PATH" ]; then WP_PATH="/var/www/html"; fi

mkdir -p $BACKUP_DIR

echo "Starting universal backup for $SITE_NAME..."
echo "Using App Container: $APP_CONTAINER"
echo "Using Database Container: $DB_CONTAINER"

# 3. PHP-Based Credential Extraction (The "Engine-Parsed" Method)
echo "Resolving live credentials via PHP engine..."
# We use PHP to include the config and echo the constants, ensuring we get the final resolved values
DB_NAME=$(docker exec $APP_CONTAINER php -r "include 'wp-config.php'; echo DB_NAME;")
DB_USER=$(docker exec $APP_CONTAINER php -r "include 'wp-config.php'; echo DB_USER;")
DB_PASS=$(docker exec $APP_CONTAINER php -r "include 'wp-config.php'; echo DB_PASSWORD;")

# 4. Hybrid Dump Logic
if [ ! -z "$DB_CONTAINER" ]; then
    echo "Checking for internal binaries in $DB_CONTAINER..."
    HAS_BIN=$(docker exec $DB_CONTAINER sh -c 'command -v mariadb-dump || command -v mysqldump' 2>/dev/null)

    if [ ! -z "$HAS_BIN" ]; then
        echo "Running internal dump using resolved config..."
        docker exec $DB_CONTAINER sh -c "exec $HAS_BIN -u '$DB_USER' -p'$DB_PASS' '$DB_NAME'" > $BACKUP_DIR/db.sql 2>/tmp/db_error.log
    else
        echo "Binaries missing (Slim Image). Running Sidecar dump..."
        docker run --rm \
            --network container:$DB_CONTAINER \
            mariadb:latest \
            mariadb-dump -h 127.0.0.1 -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > $BACKUP_DIR/db.sql 2>/tmp/db_error.log
    fi

    # Final Validation
    if [ ! -s $BACKUP_DIR/db.sql ] || grep -q "Access denied" $BACKUP_DIR/db.sql; then
        echo "Error: Database dump failed. PHP-resolved credentials may lack root privileges."
        cat /tmp/db_error.log
        exit 1
    fi
else
    echo "Error: Database container not found."
    exit 1
fi

# 5. Archive
echo "Archiving files..."
tar -czf $BACKUP_DIR/$FILE_NAME -C $WP_PATH . -C $BACKUP_DIR db.sql

# 6. Upload to DO Spaces
echo "Uploading to DigitalOcean Spaces..."
s3cmd put $BACKUP_DIR/$FILE_NAME s3://weown-dev-backup/ \
    --access_key="$SPACES_ACCESS_KEY" \
    --secret_key="$SPACES_SECRET_KEY" \
    --host="atl1.digitaloceanspaces.com" \
    --host-bucket="%(bucket)s.atl1.digitaloceanspaces.com"

# 7. Cleanup
if [ $? -eq 0 ]; then
    rm $BACKUP_DIR/$FILE_NAME
    rm $BACKUP_DIR/db.sql
    echo "Backup successful: $FILE_NAME uploaded."
else
    echo "Upload failed!"
    exit 1
fi