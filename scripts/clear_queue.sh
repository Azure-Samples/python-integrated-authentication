# Command to clear all messages. This script depends on environment
# variables created in provision.cmd.

az storage message clear --connection-string $MAIN_APP_STORAGE_CONN_STRING --queue-name $STORAGE_QUEUE_NAME
