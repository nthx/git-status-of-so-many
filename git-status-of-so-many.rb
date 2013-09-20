#!/usr/bin/env ruby

require 'fileutils'
require 'yaml'
require 'benchmark'
require 'optparse'

GIT_MSG_NO_CHANGE="nothing to commit (working directory clean)"
GIT_MSG_HAS_COMMITS="Your branch is ahead of"
GIT_MSG_IS_DIRTY="Changes not staged for commit"
GIT_MSG_TO_COMMIT="Changes to be committed"


class GitProjectsStatus
  def start(cmd)
    @options = cmd
    @repos = find_repos(@options.repos_home)
    show
    bye_bye
  end

  private
  def show
    @repos.each {|repo| show_status repo }
  end

  def bye_bye
    no_of_repos_modified = @repos.count {|r| r[:has_sth_to_show]}
    puts green "OK. #{no_of_repos_modified} repos dirty"
  end

  def show_status(repo)
    gather_git_info! repo
    puts_repo_on_screen repo
  end

  def gather_git_info!(repo)
    repo[:name] = repo[:dir]
    repo[:git] = gather_git_state(repo)
    repo[:stashes] = gather_stashes(repo)
    repo[:branch] = gather_branch(repo)
    repo[:untracked] = gather_untracked(repo)
    repo[:has_not_staged] = gather_not_staged(repo)
    repo[:has_commits_to_push] = gather_commits_to_push(repo)
    repo[:commits_to_push] = gather_no_of_commits_to_push(repo)

    repo[:has_sth_to_show] = false
    repo[:has_sth_to_show] = true if repo[:untracked]
    repo[:has_sth_to_show] = true if repo[:stashes].length > 0
    repo[:has_sth_to_show] = true if repo[:has_not_staged]
    repo[:has_sth_to_show] = true if repo[:commits_to_push] > 0
  end

  def gather_git_state(repo)
    `cd #{repo[:dir]}; git status`.to_s.strip.split "\n"
  end

  def gather_stashes(repo)
    `cd #{repo[:dir]}; git stash list`.to_s.strip.split "\n"
  end

  def gather_branch(repo)
    branch = repo[:git].grep(/branch/)
    if branch
      branch[0].to_s[12..-1].to_s.strip
    else
      '?'
    end
  end

  def gather_untracked(repo)
    repo[:git].grep(/untracked files/).length > 0
  end

  def gather_not_staged(repo)
    repo[:git].grep(/#{GIT_MSG_IS_DIRTY}/).length > 0
  end

  def gather_commits_to_push(repo)
    repo[:git].grep(/#{GIT_MSG_HAS_COMMITS}/).length > 0
  end

  def gather_no_of_commits_to_push(repo)
    return 0 unless repo[:has_commits_to_push]

    commits_to_push = repo[:git].grep(/#{GIT_MSG_HAS_COMMITS}/)[0].split " by "
    if commits_to_push.length > 0
      commits_to_push[1].to_i
    else
      1
    end
  end

  def puts_repo_on_screen(repo)
    return unless repo[:has_sth_to_show]

    puts "cd #{yellow repo[:dir]}; git st; git sl"
    puts "#{repo[:branch]}"

    return if @options.silent

    if repo[:stashes].length > 0
      puts yellow "STASHES:"
      repo[:stashes].each {|stash| puts "  #{stash}"}
    end
    if repo[:untracked]
      puts red "Has untracked files"
    end
    if repo[:has_not_staged]
      puts yellow "Has #{GIT_MSG_IS_DIRTY}"
    end
    if repo[:has_commits_to_push]
      puts red "Has commits to push: #{repo[:commits_to_push]}"
    end
    puts "\n"
  end

  def find_repos(repos_home)
    #will only find repos 3-lvls deep
    dirs = Dir.glob(["#{repos_home}/*", "#{repos_home}/*/*", "#{repos_home}/*/*/*"])
    dirs = dirs.select {|dir| dir if File.directory?(dir) and File.directory?("#{dir}/.git")}
    dirs.map {|dir| {:dir => dir}}
  end
end


module Colors
  # green "Hello"
  #   => "\e[32mHello\e[0m"
  def self.colorize(text, color_code)
    "\033[#{color_code}m#{text}\033[0m"
  end

  {
    :black    => 30,
    :red      => 31,
    :green    => 32,
    :yellow   => 33,
    :blue     => 34,
    :magenta  => 35,
    :cyan     => 36,
    :white    => 37
  }.each do |key, color_code|
    Object.send(:define_method, key) do |text|
      Colors.colorize(text, color_code)
    end
  end
end

def slowdown(secs, message)
  print message
  print yellow " Continue in: "
  secs.downto(0) do |i|
    sleep 1
    print yellow "#{i}.."
  end
  puts green "OK"
end

def question(message='')
  puts "#{message}"
  puts blue "Press [ENTER] to continue. CTRL-C to abort."
  begin
    input = STDIN.gets.strip
  rescue Exception => e
    puts
    exit
  end
end


class CmdLineParser
  attr_reader :cmd

  def initialize
    cmdStruct = Struct.new(:verbose, :repos_home, :silent)
    @cmd = cmdStruct.new
  end

  def parse
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: git-status-of-so-many.rb [options]"
      opts.on("-v", "--[no-]verbose", "Run verbosely") do |o|
        @cmd.verbose = o
      end
      opts.on("-s", "--silent", "Run with little output") do |o|
        @cmd.silent = o
      end
    end
    parser.parse!(ARGV)
  end

  def read_settings
    verify_settings_exist
    setup_home_variable!
  end

  private
  def verify_settings_exist
    if !File.exists? 'settings.yml'
      puts red "Configure me first!:"
      puts red "cp settings.yml.example settings.yml"
      puts red "vim settings.yml"
      exit
    end
  end

  def setup_home_variable!
    begin
      cnf = YAML::load(File.open('settings.yml'))
      @cmd.repos_home = cnf['settings']['your_home_of_all_git_repos']
    rescue Exception => e
      puts red "Sth wrong with reading: settings. Remove and run/configure again. \nError: #{e.message}"
      exit
    end
  end
end


cmdLineParser = CmdLineParser.new
cmdLineParser.parse
cmdLineParser.read_settings

GitProjectsStatus.new.start(cmdLineParser.cmd)

