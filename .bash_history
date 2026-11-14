python3 -m zipfile -e StrategycaServer-linux.zip . && |s -| && |sb_release-d

python3 -m zipfile -e StrategycaServer-linux.zip . && ls -l && lsb_release -d
[200~getent hosts strategyca.duckdns.org~
getent hosts strategyca.duckdns.org
bash install.sh strategyca.duckdns.org
sed -i -E 's/"contactEmail": *"[^"]*"/"contactEmail": "thefilmaly@gmail.com"/' /var/lib/strategyca/server-config.json && chown strategyca: /var/lib/strategyca/server-config.json && systemctl restart strategyca && grep contactEmail /var/lib/strategyca/server-config.json
