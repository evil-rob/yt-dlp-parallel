# yt-dlp Parallel Orchestrator

Download several videos in parallel.

## Description

This is a POSIX shell script that will take a list of video links and download
each of them in parallel processes. If you supply a cookies.txt file with a
YouTube token, the script will mark each YouTube video as played.

## Getting Started
Install it and use it.

### Dependencies

yt-dlp and any POSIX complient shell.

### Installing

* Download the script and place it in a folder in your path.
* Mark script executable.

### Executing program

* Run the script like any normal shell script.
* Supply a list of URLs on the argument list.
* A cookies file can be supplied as an environment variable.
```
$ cookies=/path/to/cookies/cookies.txt yt-dlp-par.sh https://www.youtube.com/watch?v=video1 https://www.youtube.com/watch?v=video2
```

## Help

Check the help.
```
yt-dlp-par.sh -h
```

## Authors

Robert Blank

[@evilrob@mastodon.social](https://mastodon.social/@evilrob)

## Version History

* 0.1
    * Initial Release

## License

This project is licensed under the [CC0 1.0 Universal] License - see the LICENSE.md file for details

## Acknowledgments

Inspiration, code snippets, etc.
* [awesome-readme](https://github.com/matiassingers/awesome-readme)
* [PurpleBooth](https://gist.github.com/PurpleBooth/109311bb0361f32d87a2)
* [dbader](https://github.com/dbader/readme-template)
* [zenorocha](https://gist.github.com/zenorocha/4526327)
* [fvcproductions](https://gist.github.com/fvcproductions/1bfc2d4aecb01a834b46)
