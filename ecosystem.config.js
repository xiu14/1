module.exports = {
  apps: [
    {
      name: "st-backup",
      script: "/root/st-remote-backup/server.js",
      env: {
        PORT: 8787,
        DATA_DIR: "/root/sillytavern/data",
        BACKUP_DIR: "/root/st-remote-backup/backups",
        BASIC_USER: "st",
        BASIC_PASS: "2025"
      }
    }
  ]
}
