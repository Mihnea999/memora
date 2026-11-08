---
name: media
when: Music, videos, podcasts: play, pause, skip, what is playing, volume, opening a song or film.
---
# Media

- What is playing and control: `media(action="status"|"play"|"pause"|"toggle"|"next"|"previous")`.
  Works with the Player, the Browser (YouTube, Spotify web) and most players.
- Volume: `system_setting(volume, …)`.
- Play a file: `open(path)` (opens in Player). Find music: `find_files(name="*.mp3", folder="~/Music")`.
- Play something online: `browse(url="https://www.youtube.com/results?search_query=…")`, then
  click the first result with the screen tools if the person asked to play it.
