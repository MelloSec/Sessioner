Reaches out over DCOM, establishes a session to quick configure WinRM and establish a session. Works with local or domain admin. Reset changes with reset.ps1

```
./sessioner.ps1 -servername $target -ipaddress $yours -username $admin (Or "$domain\$admin")
./reset.ps1 ./sessioner.ps1 -servername $target -ipaddress $yours -username $admin
```
