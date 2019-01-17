# Find-File.ps1  *  Searches for files and/or directories on Win and Linux.
# Origionally Written by Bill Stewart (bill.stewart@frenchmortuary.com)
# Updated by Brian Lewis (lwbr@amazon.com)

param ($Name,
       $Path,
       $LastWriteTimeRange,
       $SizeRange,
       [Switch] $OneLevel,
       [Switch] $Files,
       [Switch] $Dirs,
       [Switch] $Force,
       [Switch] $DefaultFormat,
       [Switch] $Help)

$global:findfileversion = "Version 2.2"

# Displays a usage message and ends the script.
function usage {
  $scriptname = $SCRIPT:MYINVOCATION.MyCommand.Name

  "POWERSHELL SCRIPT NAME: $scriptname  $findfileversion"
  ""
  "SYNOPSIS"
  "    A tool that searches for files and/or directories."
  ""
  "SYNTAX"
  "    $scriptname -name <String[]> [-path <String[]>]"
  "    [-lastwritetimerange <DateTime[]> [-sizerange <UInt64[]> [-onelevel]"
  "    [-files] [-dirs] [-force] [-defaultformat]"
  ""
  "EXAMPLES"
  ""
  "   set-alias find-file ./find-file.ps1   # setting this alias enables you to just type ‘find-file’ instead of .\find-file.ps1"
  "             find-file blewis.txt"
  "             find-file blewis.txt -path c:\users"
  "             find-file blewis.txt c:\users -Force"
  "             find-file *blewis* -path c:\users -SizeRange 55000,10000000"
  "             find-file blewis* -path c:\users -LastWriteTimeRange 4/18/2014,6/18/2014"
  ""
  "PARAMETERS"
  "    -name <String[]>"
  "        Searches for items that match the specified wildcard pattern(s)."
  ""
  "    -path <String[]>"
  "        Searches for items in the specified location(s). If not specified, the"
  "        default is to search all local fixed drives."
  ""
  "    -lastwritetimerange <DateTime[]>"
  "        Limits output to items matching a date range. A single value means"
  "        items modified from the specified date and later. An array is"
  "        interpreted as an inclusive date range where the first element is the"
  "        earliest date and the second element is the latest date. A zero for the"
  "        first element means no earliest date."
  ""
  "    -sizerange <UInt64[]>"
  "        Limits output to files matching a size range. A single value means"
  "        files must be at least the specified size. An array is interpreted as"
  "        an inclusive size range where the first element is the smallest size"
  "        and the second element is the largest size."
  ""
  "    -onelevel"
  "        This parameter limits searches to the specified path(s). Subdirectories"
  "        are not searched."
  ""
  "    -files"
  "        Searches for files. This is the default. To search for both files and"
  "        directories, specify both -files and -dirs."
  ""
  "    -dirs"
  "        Searches for directories. To search for both files and directories,"
  "        specify both -files and -dirs."
  ""
  "    -force"
  "        Expands the search to find items with hidden and system attributes."
  ""
  "    -defaultformat"
  "        Outputs items using the default formatter instead of formatted"
  "        strings."

  exit
}

# Returns whether the specified value is numeric.
function isNumeric($value) {
  [Decimal], [Double], [Int32], [Int64],
  [Single], [UInt32], [UInt64] -contains $value.GetType()
}

# Outputs the specified file system item. With -defaultformat,
# output the item using the default formatter; otherwise, output a
# formatted string.
function writeItem($item) {
  if ($DefaultFormat) {
    "{0} {1:yyyy-MM-dd HH:mm} {2,15:N0} {3}" -f $item.Mode,
      $item.LastWriteTime, $item.Length, $item.FullName
  }
  else {
    
   $item | Select-Object Name,Directory 
  }
}

function main {
  # If -help is present or the -name parameter is missing, output
  # the usage message.
  if (($Help) -or (-not $Name)) {
    usage
  }

  # Convert $Name to an array. If any array element contains *,
  # change the array to $NULL. This is because
  #   get-childitem c:\* -include *
  # recurses to one level even if you don't use -recurse.
  $Name = @($Name)
  for ($i = 0; $i -lt $Name.Length; $i++) {
    if ($Name[$i] -eq "*") {
      $Name = $NULL
      break
    }
  }

  #CALLOUT A
  # If no -path parameter, use Get-Cim to collect a list of fixed drives on Windows and user / on Linux & Mac.
  if (-not $Path)
  {
    if ($PSVersionTable.PSEdition -match "Desktop")
    {
      $Path = Get-CimInstance -ClassName Win32_LogicalDisk -filter DriveType=3 | foreach-object { $_.DeviceID }
    }
    elseif ($PSVersionTable.OS -match "Windows") {
      $Path = Get-CimInstance -ClassName Win32_LogicalDisk -filter DriveType=3 | foreach-object { $_.DeviceID }
    }
    else 
    {
        $Path = "/"
    }
    
  }
  #END CALLOUT A

  # Convert $Path into an array so we can iterate it.
  $Path = @($Path)

  #CALLOUT B
  # If a path ends with "\", append "*". Then, if it doesn't end with
  # "\*", append "\*" so each path in the array ends with "\*".
  for ($i = 0; $i -lt $Path.Length; $i++) {
    if ($Path[$i].EndsWith("\")) {
      $Path[$i] += "*"
    }
    if (-not $Path[$i].EndsWith("\*")) {
      $Path[$i] += "\*"
    }
  }
  #END CALLOUT B

  # If no -LastWriteTimeRange parameter, assume all dates.
  if (-not $LastWriteTimeRange) {
    $LastWriteTimeRange = @([DateTime]::MinValue, [DateTime]::MaxValue)
  }
  else {
    # Convert $LastWriteTimeRange to an array (if it's not already).
    $LastWriteTimeRange = @($LastWriteTimeRange)
    # If only one element, add max date as second element.
    if ($LastWriteTimeRange.Length -eq 1) {
      $LastWriteTimeRange += [DateTime]::MaxValue
    }
    # Zero for first element means [DateTime]::MinValue.
    if ($LastWriteTimeRange[0] -eq 0) {
      $LastWriteTimeRange[0] = [DateTime]::MinValue
    }
    #CALLOUT C
    # Throw an error if [DateTime]::Parse() fails.
    trap [System.Management.Automation.MethodException] {
      throw "Error parsing date range. String not recognized as a valid DateTime."
    }
    # Parse the first two array elements as DateTimes.
    for ($i = 0; $i -lt 2; $i++) {
      $LastWriteTimeRange[$i] = [DateTime]::Parse($LastWriteTimeRange[$i])
    }
    #END CALLOUT C
  }

  # Throw an error if the date range is invalid.
  if ($LastWriteTimeRange[0] -gt $LastWriteTimeRange[1]) {
    throw "Invalid date range. The first date is greater than the second."
  }

  # If no -sizerange parameter, assume all sizes.
  if (-not $SizeRange) {
    $SizeRange = @(0, [UInt64]::MaxValue)
  }
  else {
    # Convert $SizeRange to an array (if it's not already).
    $SizeRange = @($SizeRange)
    # If no second element, add max value as second element.
    if ($SizeRange.Length -eq 1) {
      $SizeRange += [UInt64]::MaxValue
    }
  }

  #CALLOUT D
  # Ensure the elements in the size range are numeric.
  for ($i = 0; $i -lt 2; $i++) {
    if (-not (isNumeric $SizeRange[$i])) {
      throw "Size range must contain numeric value(s)."
    }
  }
  #END CALLOUT D

  # Throw an error if the size range is invalid.
  if ($SizeRange[0] -gt $SizeRange[1]) {
    throw "Invalid size range. The first size is greater than the second."
  }

  # If both -files and -dirs are missing, assume -files.
  if ((-not $Files) -and (-not $Dirs)) {
    $Files = $TRUE
  }

  # Keep track of the number of files and their sizes.
  $count = $sizes = 0

  # Use the get-childitem cmdlet to search the file system, and use
  # the writeItem function to output matching items. For files, check
  # the date and size ranges. For directories, only the date range is
  # meaningful.
  get-childitem $Path -include $Name -ErrorAction SilentlyContinue -force: $Force -recurse: (-not $OneLevel) | foreach-object {
    if ($Files -and (-not $_.PsIsContainer)) {
      if (($_.LastWriteTime -ge $LastWriteTimeRange[0]) -and ($_.LastWriteTime -le $LastWriteTimeRange[1]) -and
          ($_.Length -ge $SizeRange[0]) -and ($_.Length -le $SizeRange[1])) {
        $count++
        $sizes += $_.Length
        writeItem $_
      }
    }
    if ($Dirs -and ($_.PsIsContainer)) {
      if (($_.LastWriteTime -ge $LastWriteTimeRange[0]) -and ($_.LastWriteTime -le $LastWriteTimeRange[1])) {
        $count++
        writeItem $_
      }
    }
  }

  # Output statistics if not using -defaultformat.
  if (-not $DefaultFormat) {
    "Found {0:N0} item(s), {1:N0} byte(s)" -f $count, $sizes
  }
}

main