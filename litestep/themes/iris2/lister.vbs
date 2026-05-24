On Error Resume Next
Dim fso, folder, files, sFolder
Dim MyInitials, MyName, MyNames
strPath = Wscript.ScriptFullName
Set objFSO = CreateObject("Scripting.FileSystemObject")
Set objFile = objFSO.GetFile(strPath)
strFolder = objFSO.GetParentFolderName(objFile) 
Set objFSO = CreateObject("Scripting.FileSystemObject")
strFileName = "launcher.rc"
strFullName = objFSO.BuildPath(strFolder, strFileName)
Set objFile = objFSO.CreateTextFile(strFullName)

Set objShell = CreateObject("Wscript.Shell")
sFolder = Wscript.Arguments.Item(0)
If sFolder = "" Then
Wscript.Echo "No Folder parameter was passed"
Wscript.Quit
End If
Set fso = CreateObject("Scripting.FileSystemObject")
Set folder = fso.GetFolder(sFolder)
Set files = folder.Files

For each folderIdx In files
If folderIdx.Name = "desktop.ini" Then
Else
i = i + 1
MyNames = Split(fso.getbasename(folderIdx.Name), " ")
For Each MyName In MyNames
If Len(MyName) > 0 Then MyInitials = MyInitials & UCase(Left(MyName,1))
Next
objFile.WriteLine("App" &i & "Name """ & MyInitials & """")
objFile.WriteLine("App" &i & "Path """ & folderIdx.Path & """")
MyInitials = ""
End If
Next
objFile.Close


