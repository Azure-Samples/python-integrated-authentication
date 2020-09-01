@echo off
:: With all the pieces in place from provision.cmd, invoke the app's 
:: API endpoint, which returns JSON with a code and a timestamp. The
:: code uses a number from the third-party API endpiont.

echo Invoking API endpoint https://%MAIN_APP_NAME%.azurewebsites.net/api/v1/getcode

call az rest --method get --uri "https://%MAIN_APP_NAME%.azurewebsites.net/api/v1/getcode"

:: When a code is retrieved, a message is written to the storage queue.
:: We can retrieve the latest message to show that it was written. The
:: "get" command used here removes the message from the queue, so you
:: can run this test.cmd script again to invoke the API and generate and
:: retrieve another message. The messages remain in the queue, but you
:: can clear the queue by running the same command below replacing "get"
:: with "clear".
::
:: Reference: https://docs.microsoft.com/cli/azure/storage/message?view=azure-cli-latest#commands

echo Retrieving the most recent message from the queue

call az storage message get --connection-string %MAIN_APP_STORAGE_CONN_STRING% --queue-name %STORAGE_QUEUE_NAME%

echo After a few minutes, you may start to see earlier messages in the queue.
echo To clear the queue, run the command in clear_queue.cmd.
