#!/usr/bin/env python3
"""Symbols that can be engraved on a folder (System > Folder Colour & Symbol).

Builds system/shell/ui/glyphs.js from Phosphor Icons' "fill" set (MIT,
https://phosphoricons.com), the filled style closest to the symbols a Mac
engraves on folders. Only the curated list below is kept.

    curl -sL https://registry.npmjs.org/@phosphor-icons/core/-/core-2.1.1.tgz | tar xz
    tools/folder-glyphs.py package/assets/fill > system/shell/ui/glyphs.js
"""
import json
import os
import re
import sys

# group -> [(our name, phosphor name, words to search by)]
GROUPS = [
    ("Work", [
        ("doc", "file-text", "document text paper"), ("docs", "files", "documents copies"),
        ("briefcase", "briefcase", "work job office"), ("folder", "folder-simple", "folder"),
        ("archive", "archive", "box archive storage"), ("tray", "tray", "inbox tray"),
        ("clipboard", "clipboard-text", "clipboard list tasks"), ("checklist", "list-checks", "todo tasks checklist"),
        ("calendar", "calendar-blank", "calendar date schedule"), ("chart", "chart-bar", "chart stats data"),
        ("pie", "chart-pie-slice", "pie chart report"), ("presentation", "presentation-chart", "slides presentation"),
        ("table", "table", "spreadsheet table"), ("receipt", "receipt", "receipt invoice bills"),
        ("money", "currency-dollar", "money finance dollar"), ("euro", "currency-eur", "euro money"),
        ("bank", "bank", "bank finance taxes"), ("wallet", "wallet", "wallet money"),
        ("creditcard", "credit-card", "card payment"), ("signature", "signature", "sign contract"),
        ("stamp", "stamp", "stamp official"), ("paperclip", "paperclip", "attachment clip"),
        ("pen", "pen-nib", "write design pen"), ("pencil", "pencil-simple", "edit draft pencil"),
        ("envelope", "envelope-simple", "mail letter email"), ("phone", "phone", "phone call"),
        ("printer", "printer", "print printer"), ("building", "buildings", "company office city"),
    ]),
    ("School", [
        ("book", "book", "book reading"), ("bookopen", "book-open", "book read study"),
        ("books", "books", "library books"), ("bookmark", "bookmark-simple", "bookmark saved"),
        ("graduation", "graduation-cap", "school university graduation"), ("student", "student", "student class"),
        ("exam", "exam", "exam test"), ("notebook", "notebook", "notebook notes"),
        ("note", "note", "note memo"), ("atom", "atom", "science physics"),
        ("flask", "flask", "chemistry lab"), ("dna", "dna", "biology dna"),
        ("math", "math-operations", "maths numbers"), ("function", "function", "maths formula"),
        ("translate", "translate", "language translate"), ("globe", "globe-hemisphere-west", "world geography globe"),
        ("lightbulb", "lightbulb", "idea lightbulb"), ("brain", "brain", "brain mind think"),
        ("certificate", "certificate", "certificate diploma"), ("ruler", "ruler", "ruler measure"),
    ]),
    ("Media", [
        ("photo", "image", "photo picture image"), ("photos", "images", "photos album pictures"),
        ("camera", "camera", "camera photography"), ("film", "film-strip", "film movie video"),
        ("video", "video-camera", "video record"), ("television", "television-simple", "tv series shows"),
        ("music", "music-notes", "music songs"), ("note1", "music-note", "music note song"),
        ("headphones", "headphones", "music audio listen"), ("microphone", "microphone", "podcast voice record"),
        ("speaker", "speaker-hifi", "speaker audio"), ("vinyl", "vinyl-record", "record album vinyl"),
        ("guitar", "guitar", "guitar instrument"), ("piano", "piano-keys", "piano keys"),
        ("palette", "palette", "art paint colours"), ("paintbrush", "paint-brush", "paint brush art"),
        ("pentool", "pen-nib-straight", "vector design"), ("shapes", "shapes", "shapes design"),
        ("filmslate", "film-slate", "cinema director"), ("popcorn", "popcorn", "movies popcorn"),
        ("ticket", "ticket", "ticket event"), ("aperture", "aperture", "lens photography"),
    ]),
    ("Tech", [
        ("code", "code", "code programming"), ("terminal", "terminal-window", "terminal shell"),
        ("brackets", "brackets-curly", "json code"), ("bug", "bug", "bug debug"),
        ("gitbranch", "git-branch", "git branch"), ("database", "database", "database data"),
        ("cpu", "cpu", "cpu chip hardware"), ("desktop", "desktop", "computer desktop"),
        ("laptop", "laptop", "laptop computer"), ("device", "device-mobile", "phone mobile"),
        ("tablet", "device-tablet", "tablet ipad"), ("gamepad", "game-controller", "games controller"),
        ("joystick", "joystick", "arcade games"), ("robot", "robot", "robot ai bot"),
        ("sparkle", "sparkle", "ai magic sparkle"), ("cloud", "cloud", "cloud sync"),
        ("download", "download-simple", "download"), ("upload", "upload-simple", "upload"),
        ("wifi", "wifi-high", "wifi network"), ("plug", "plug", "plug power"),
        ("battery", "battery-full", "battery"), ("harddrive", "hard-drives", "server drive backup"),
        ("usb", "usb", "usb stick"), ("gear", "gear", "settings config"),
        ("wrench", "wrench", "tools fix"), ("toolbox", "toolbox", "toolbox tools"),
        ("key", "key", "key password secret"), ("lock", "lock-simple", "lock private secret"),
        ("shield", "shield-check", "security safe"), ("fingerprint", "fingerprint", "identity fingerprint"),
        ("package", "package", "package box software"), ("puzzle", "puzzle-piece", "plugin puzzle extension"),
    ]),
    ("Life", [
        ("house", "house", "home house"), ("heart", "heart", "love heart favourite"),
        ("star", "star", "star favourite"), ("smiley", "smiley", "happy smile face"),
        ("user", "user", "person user"), ("users", "users-three", "family friends people"),
        ("baby", "baby", "baby kids"), ("dog", "dog", "dog pet"), ("cat", "cat", "cat pet"),
        ("pawprint", "paw-print", "pets animals"), ("gift", "gift", "gift present birthday"),
        ("cake", "cake", "birthday cake party"), ("confetti", "confetti", "party celebrate"),
        ("coffee", "coffee", "coffee cafe"), ("forkknife", "fork-knife", "food recipes restaurant"),
        ("cookingpot", "cooking-pot", "cooking recipes"), ("wine", "wine", "wine drinks"),
        ("pizza", "pizza", "pizza food"), ("shoppingcart", "shopping-cart", "shopping groceries"),
        ("bag", "shopping-bag", "shopping bag"), ("tshirt", "t-shirt", "clothes fashion"),
        ("heartbeat", "heartbeat", "health medical"), ("pill", "pill", "medicine health"),
        ("barbell", "barbell", "gym fitness sport"), ("run", "person-simple-run", "running sport"),
        ("bicycle", "bicycle", "bike cycling"), ("soccer", "soccer-ball", "football soccer"),
        ("basketball", "basketball", "basketball sport"), ("trophy", "trophy", "trophy win award"),
        ("medal", "medal", "medal award"), ("flag", "flag", "flag goal"),
        ("church", "church", "church"), ("handheart", "hand-heart", "charity care"),
    ]),
    ("Travel", [
        ("airplane", "airplane-tilt", "travel flight plane"), ("car", "car-profile", "car driving"),
        ("train", "train", "train travel"), ("boat", "boat", "boat sea"),
        ("suitcase", "suitcase-rolling", "travel luggage holiday"), ("map", "map-trifold", "map trips"),
        ("pin", "map-pin", "place location"), ("compass", "compass", "compass explore"),
        ("tent", "tent", "camping"), ("mountains", "mountains", "mountains hiking"),
        ("tree", "tree", "tree nature"), ("leaf", "leaf", "leaf nature plants"),
        ("flower", "flower", "flower garden"), ("plant", "plant", "plant garden"),
        ("sun", "sun", "sun summer"), ("moon", "moon", "moon night"),
        ("cloudsun", "cloud-sun", "weather"), ("snowflake", "snowflake", "winter snow"),
        ("umbrella", "umbrella", "rain umbrella"), ("fire", "fire", "fire hot"),
        ("drop", "drop", "water drop"), ("waves", "waves", "sea beach waves"),
        ("island", "island", "island beach holiday"), ("globeeu", "globe-hemisphere-east", "world travel"),
    ]),
    ("Symbols", [
        ("bolt", "lightning", "lightning fast power"), ("bell", "bell", "bell alerts"),
        ("tag", "tag", "tag label"), ("pushpin", "push-pin", "pin important"),
        ("warning", "warning", "warning important"), ("info", "info", "info about"),
        ("question", "question", "help question"), ("check", "check-circle", "done check"),
        ("x", "x-circle", "no cancel"), ("clock", "clock", "time recent"),
        ("hourglass", "hourglass-medium", "waiting later"), ("trash", "trash", "trash delete"),
        ("eye", "eye", "watch view"), ("eyeslash", "eye-slash", "hidden private"),
        ("crown", "crown", "crown king best"), ("diamond", "diamond", "diamond gem"),
        ("rocket", "rocket-launch", "rocket launch project"), ("target", "target", "target goal"),
        ("infinity", "infinity", "infinity"), ("peace", "peace", "peace"),
        ("yinyang", "yin-yang", "balance"), ("anchor", "anchor", "anchor"),
        ("chat", "chat-circle-dots", "chat messages"), ("hash", "hash", "hash number"),
        ("at", "at", "email at"), ("asterisk", "asterisk", "asterisk"),
        ("arrowdown", "arrow-circle-down", "downloads"), ("arrowup", "arrow-circle-up", "uploads"),
        ("recycle", "recycle", "recycle reuse"), ("ghost", "ghost", "ghost halloween"),
        ("skull", "skull", "skull danger"), ("alien", "alien", "alien space"),
    ]),
]


def main():
    src = sys.argv[1]
    glyphs, groups, words, seen = {}, [], {}, set()
    for group, items in GROUPS:
        names = []
        for name, ph, w in items:
            assert name not in seen, name
            seen.add(name)
            with open(os.path.join(src, ph + "-fill.svg")) as f:
                svg = f.read()
            paths = re.findall(r'<path d="([^"]+)"', svg)
            glyphs[name] = " ".join(paths)
            words[name] = w
            names.append(name)
        groups.append({"name": group, "symbols": names})
    print(".pragma library")
    print("// Generated by tools/folder-glyphs.py from Phosphor Icons (fill), MIT License,")
    print("// Copyright (c) 2023 Phosphor Icons. 256x256 paths.")
    print("var paths = " + json.dumps(glyphs, separators=(",", ":")))
    print("var groups = " + json.dumps(groups, separators=(",", ":")))
    print("var words = " + json.dumps(words, separators=(",", ":")))


if __name__ == "__main__":
    main()
