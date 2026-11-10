---
name: files
when: Finding, opening, reading, writing, organising, moving, renaming, zipping or deleting files and folders.
---
# Files

- Find: `find_files(name=…)` (by name, in the home folder by default) or
  `find_files(text=…)` to search inside documents. Places: ~/Documents, ~/Downloads,
  ~/Pictures (screenshots in ~/Pictures/Screenshots), ~/Music, ~/Videos, ~/Desktop.
- Read with `read_file` (also PDFs, .docx/.odt/.xlsx/.pptx and pictures), make a file with
  `write_file`, change part of one with `edit_file`; show a file or folder to the person with
  `open(path)` (opens in its app, folders in Files).
- Delete = `trash(action="move", paths=[…])`; it can be undone with `trash(action="restore")`.
  Never `rm` the person's files unless they ask to delete them for good.
- Moving/renaming many files: list first, show the plan in one or two lines, then do it with
  one command. Keep names readable; don't overwrite existing files (`mv -n`).
- Archives: `zip -r out.zip folder`, `tar -xf file` (also .zip with `unzip`).
- Large folders: `du -sh ~/* | sort -h` to see what takes space.
- After making a document for the person, `open` it so they see it.
