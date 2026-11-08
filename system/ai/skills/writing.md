---
name: writing
when: Writing or editing text for the person: letters, emails, documents, summaries, translations, spreadsheets, code files.
---
# Writing

- Short things (a message, an answer): write them in the chat.
- Documents: `write_file` to ~/Documents/NAME.md (or .txt), then `open` it so the person sees it
  in Text Editor. Use the person's language and a plain, natural tone.
- Tables / spreadsheets: write a .csv in ~/Documents and open it (opens in a spreadsheet app if
  one is installed, else a text editor). Say so.
- To put text into an app that is open (an email, a form): `clipboard(action="set", text=…)`, then
  `press_keys("ctrl+v", window=…)`.
- Summarise a file: `read_file` it first; summarise a web page: `web_fetch` / `fetch_url`.
