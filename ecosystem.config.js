module.exports = {
  apps: [
    {
      name: "st-backup",
      script: "/opt/st-remote-backup/server.js",
      env: {
        PORT: 8787,
        DATA_DIR: "/root/st2/data",
        BACKUP_DIR: "/opt/st-remote-backup/backups",
        BASIC_USER: "xiu",
        BASIC_PASS: "960718"
      }
    }
  ]
}
