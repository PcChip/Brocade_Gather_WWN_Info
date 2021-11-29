#Brocade - collect WWNs from Aliases and Zones
#gather info about each WWN
#tested with FOS v7.2.1
#Mike Dawson 7/28/2021

import-module posh-ssh

New-SSHSession -ComputerName "10.100.100.50" -Credential (Get-Credential admin)
$switchName = (Invoke-SSHCommand -index 0 -Command "switchname").output

class WWNInfo {
    [string]$Alias      = "Undefined"
    [string]$Zone       = "Undefined"
      [bool]$Alive      = $true
    [string]$SwitchName = "Undefined"
    [string]$PortNum    = "Undefined"
}

$alishow_CMD     = "alishow | grep alias"
$alishow_Results = (Invoke-SSHCommand -index 0 -Command $alishow_CMD).output

$Aliases = $alishow_Results.foreach({$_.split(': ')[-1]})  
$Aliases = $Aliases.trimstart()
$Aliases = $Aliases.trimEnd()

$OutputTable = @()

$WWN_Hashtable = New-Object 'System.Collections.Generic.Dictionary[String,WWNInfo]'

foreach($Alias in $Aliases)
{
    $single_alishow_CMD = "alishow " + $Alias
    $single_alishow_Result = (Invoke-SSHCommand -index 0 -Command $single_alishow_CMD).output
    
    $WWNs = $single_alishow_Result.split(' ')

    foreach($WWN in $WWNs)
    {
        if($WWN -notlike "*:??:*")
        {
            continue #skip this line
        }

        $WWN = $WWN.trimstart()   #trim whitespace from beginning
        $WWN = $WWN.trimend()     #trim whitespace from beend
        $WWN = $WWN -replace ';'  #strip out semicolons

        $WWN_Entry = [WWNInfo]::new()
        $WWN_Entry.Alias = $Alias
        $WWN_Entry.SwitchName = $switchName

        $WWN_Hashtable[$WWN] = $WWN_Entry #create new WWN entry in the hashtable (note: Zone will be "undefined" at this point, and Alive will be "true")

    }
    
}



$zoneHashtable = @{}

$zones = (Invoke-SSHCommand -index 0 -Command "zoneshow").output

$num = $zones.indexof('Effective configuration:')

$num += 1

$zoneName = "UNDEFINED"

for($num ; $num -lt $zones.count; $num++)
{
    if($zones[$num] -like "*zone:*") #this line is a Zone name, create a new entry in the zoneHashtable
    {
        $zoneName = $zones[$num].split('zone:')[-1]
        $zoneName = $zoneName.trimstart()
        $zoneName = $zoneName.trimEnd()

        $zoneHashtable[$zoneName] = @() #create empty array in this new entry
    }
    else  #this line is a WWN
    {
        $WWN = $zones[$num]
        if($WWN -notlike "*:??:*")
        {
            write-host "Error: expected WWN but got " $WWN
            continue 
        }
        
        $WWN = $WWN.trimstart()   #trim whitespace from beginning
        $WWN = $WWN.trimend()     #trim whitespace from beend
        $WWN = $WWN -replace ';'  #strip out semicolons
         
        $zoneHashtable[$zoneName] += $WWN

        if($WWN_Hashtable.ContainsKey($WWN)) #this WWN is already in the table, just fill in Zone name
        {
            $WWN_Hashtable[$WWN].Zone = $zoneName
        }
        else #not already there, make a new one
        {
            $WWN_Entry = [WWNInfo]::new()
            $WWN_Entry.SwitchName = $switchName
            $WWN_Entry.Zone = $zoneName

            $WWN_Hashtable[$WWN].Zone = $WWN_Entry
        }
    }

}

# === Fill out info ====
foreach($iter in $WWN_Hashtable.GetEnumerator())
{
    write-host $iter.Key " " -ForegroundColor white -NoNewline

    $WWN = $iter.Key
    $nodeFind_CMD = "nodefind " + $WWN
    $nodeFind_Result = (Invoke-SSHCommand -index 0 -Command $nodeFind_CMD).output
    
    if($nodeFind_Result -like "No device found") #dead WWN
    {
        
        write-host $iter.Value.Alias -ForegroundColor Green -NoNewline
        write-host " contains unused WWN " -ForegroundColor Gray -NoNewline
        write-host $iter.Key -ForegroundColor Yellow

        $WWN_Hashtable[$WWN].Alive = $false #mark it as dead
        $WWN_Hashtable[$WWN].PortNum = "NOT_FOUND"

        $outputRow = New-Object System.Object

        $outputRow | add-member -MemberType NoteProperty -Name "Alias" -Value $Alias
        $outputRow | add-member -MemberType NoteProperty -Name "WWN" -Value $WWN

        $outputTable += $outputRow
    }
    else
    {
        $portindex = $nodefind_result -like "*Port Index*"
        $port = 999
        $port = $portindex[0][-1]

        $WWN_Hashtable[$WWN].Alive   = $true #mark it as alive
        $WWN_Hashtable[$WWN].PortNum = $port #record the port number it's detected on

        write-host $Alias -ForegroundColor Green -NoNewline
        write-host " contains WWN " -ForegroundColor Gray -NoNewline
        write-host $WWN -ForegroundColor cyan -NoNewline
        write-host " " which is connected to port $port -ForegroundColor white
            
    }


}


#display info
foreach($iter in $WWN_Hashtable.GetEnumerator())
{
    $alias      = $iter.value.Alias
    $portnum    = $iter.Value.PortNum
    $switchName = $iter.Value.SwitchName
    $zone       = $iter.Value.Zone
    $alive      = $iter.Value.Alive

    if(!$alive)
    {
        write-host $iter.Key " " -foregroundcolor gray -NoNewline
        Write-Host "$alias $(" " * 25)".Substring(0,25)  -ForegroundColor DarkCyan -NoNewline
        write-host "$alive $(" " * 5)".Substring(0,5) " "  -ForegroundColor DarkGreen -NoNewline
        write-host "$portnum $(" " * 10)".Substring(0,10) " " -ForegroundColor Gray -NoNewline
        write-host $SwitchName " " -ForegroundColor Gray -NoNewline
        write-host $Zone " " -ForegroundColor DarkYellow 
    }
    else
    {
        write-host $iter.Key " " -NoNewline
        Write-Host "$alias $(" " * 25)".Substring(0,25)  -ForegroundColor Cyan -NoNewline
        write-host "$alive $(" " * 5)".Substring(0,5) " " -ForegroundColor Green -NoNewline
        write-host "$portnum $(" " * 10)".Substring(0,10) " " -ForegroundColor White -NoNewline
        write-host $iter.Value.SwitchName " " -ForegroundColor Gray -NoNewline
        write-host $iter.Value.Zone " " -ForegroundColor Yellow 
  
    }
}
