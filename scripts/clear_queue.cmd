:: Command to clear all messages. This script depends on environment
:: variables created in provision.cmd.

call az storage message get --connection-string %MAIN_APP_STORAGE_CONN_STRING% --queue-name %STORAGE_QUEUE_NAME%
