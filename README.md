git-status-of-so-many
=====================

# The usecase

  Forgot to push any of 10+ git repos you work with?

  With 1 single command it tells you of your:
  * not pushed repos
  * extra stuff like existing stashes, unstages files


# Requirements

* you have all git repos under 1 dir. Example /home/user/git_repos/
* any Ruby
* was made for terminals with dark background
* these aliases in your ~/.gitconfig

        $ cat ~/.gitconfig
        [alias]
          st = status
          sl = stash list


# How to run?

* ./git-status-of-so-many.rb -h
* ./git-status-of-so-many.rb
* configure your git repos home via onscreen instructions
