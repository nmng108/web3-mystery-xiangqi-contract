yarn net --hostname 0.0.0.0 --port ${RPC_PORT:-8545} &
yarn wait-on http://127.0.0.1:${RPC_PORT:-8545} && yarn he-deploy --network local
wait $!