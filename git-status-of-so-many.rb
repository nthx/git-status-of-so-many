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
    @repos = find_repos(@options.setting_repos_home)
    process_repos
    show
    bye_bye
  end

  private
  def process_repos
    @repos.sort_by{|e| e[:dir]}.each do |repo|
      gather_git_info! repo
    end
  end

  def show
    @repos.each {|repo| show_status repo }
  end

  def bye_bye
    no_of_repos_modified = @repos.count {|r| r[:has_sth_to_show]}
    puts green "OK. #{no_of_repos_modified} repos dirty"
  end

  def show_status(repo)
    puts_repo_on_screen repo
  end

  def gather_git_info!(repo)
    repo[:name] = repo[:dir]
    puts repo[:name] if @options.opt_verbose

    repo[:git] = gather_git_state(repo)
    if @options.opt_show_stashes
      repo[:stashes] = gather_stashes(repo)
    else
      repo[:stashes] = []
    end
    repo[:branch] = gather_branch(repo)
    repo[:untracked] = gather_untracked(repo)
    repo[:has_not_staged] = gather_not_staged(repo)
    repo[:has_commits_to_push] = gather_commits_to_push(repo)
    repo[:commits_to_push] = gather_no_of_commits_to_push(repo)
    if @options.opt_show_commits_after_tag
      repo[:latest_tag], repo[:latest_tag_commit] = gather_latest_tag(repo)
      repo[:commits_after_tag], repo[:commits_after_tag_short] = gather_commits_above_latest_tag(repo)
    end

    repo[:has_sth_to_show] = false
    repo[:has_sth_to_show] = true if repo[:untracked]
    repo[:has_sth_to_show] = true if repo[:stashes].length > 0
    repo[:has_sth_to_show] = true if repo[:has_not_staged]
    repo[:has_sth_to_show] = true if repo[:commits_to_push] > 0
    repo[:has_sth_to_show] = true if @options.opt_show_commits_after_tag && repo[:commits_after_tag]

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

  def gather_latest_tag(repo)
    cmd = "cd #{repo[:dir]}; git log --simplify-by-decoration --decorate --pretty=oneline | cut -f2- -d' '| sed -e \"s/^\(HEAD, /\\(/g\" | grep \"^(tag:\" | cut -d'(' -f2- | sed -e \"s/^tag: //g\"| cut -d, -f1 | cut -d')' -f1| head -1 2> /dev/null"
    latest_tag = `#{cmd}`.to_s.strip
    return [nil, nil] if latest_tag.length == 0
    latest_tag_commit = `cd #{repo[:dir]}; git rev-list #{latest_tag}| head -1`.to_s.strip
    [latest_tag, latest_tag_commit]
  end

  def gather_commits_above_latest_tag(repo)
    return nil if not repo[:latest_tag]
    commits = `cd #{repo[:dir]}; git log --pretty=oneline #{repo[:latest_tag]}..HEAD`.to_s.strip.split "\n"
    commits_short = `cd #{repo[:dir]}; git log --pretty=oneline #{repo[:latest_tag]}..HEAD | cut -d' ' -f2-`.to_s.strip.split "\n"
    commits.length > 0 ? [commits, commits_short]: [nil, nil]
  end

  def puts_repo_on_screen(repo)
    return unless repo[:has_sth_to_show]

    header = "cd #{repo[:dir]}; git st; git sl"
    puts blue '*' * header.length
    puts blue header
    puts blue "(#{repo[:branch]})"

    return if @options.opt_silent

    if repo[:stashes].length > 0
      #puts yellow "Stashes:"
      repo[:stashes].each {|stash| puts "  #{stash}"}
    end
    if repo[:untracked]
      puts red "Has untracked files"
    end
    if repo[:has_not_staged]
      puts red "Has #{GIT_MSG_IS_DIRTY}"
    end
    if repo[:has_commits_to_push]
      puts red "Has commits to push: #{repo[:commits_to_push]}"
    end
    
    if @options.opt_show_commits_after_tag && repo[:latest_tag] && repo[:commits_after_tag]
      puts red "\nHEAD"
      puts repo[:commits_after_tag_short][0..20].map {|l| "  => #{l}"}
      puts red "Commits above: #{repo[:latest_tag].gsub('refs/tags/', '')} ^"
    end
    puts "\n\n"
  end

  def find_repos(repos_home)
    #will only find repos 3-lvls deep
    dirs = Dir.glob(["#{repos_home}/*", "#{repos_home}/*/*", "#{repos_home}/*/*/*"])

    #select dirs only
    dirs = dirs.select {|dir| dir if File.directory?(dir) and File.directory?("#{dir}/.git")}

    #filter only fav repos
    if @options.opt_fav_repos
      dirs = dirs.select do |dir|
        if @options.setting_fav_repos.any? {|pattern| "#{dir}/".match(pattern)}
          true
        else
          false
        end
      end
    end

    #filter out excluded repos
    dirs = dirs.select { |dir| @options.setting_excluded_repos.any? {|pattern| "#{dir}/".match(pattern)} ? false : true }
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
    cmdStruct = Struct.new(
      :opt_verbose, 
      :opt_silent, 
      :setting_repos_home, :setting_fav_repos, :setting_excluded_repos, 
      :opt_show_stashes, 
      :opt_show_commits_after_tag, 
      :opt_fav_repos)
    @cmd = cmdStruct.new
    #@cmd.opt_show_stashes = true
  end

  def parse
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: git-status-of-so-many.rb [options]"
      opts.on("-v", "--[no-]verbose", "Run verbosely") do |o|
        @cmd.opt_verbose = o
      end
      opts.on("-s", "--silent", "Run with little output") do |o|
        @cmd.opt_silent = o
      end
      opts.on("-t", "--above-tag-commits", "Show not tagged commits") do |o|
        @cmd.opt_show_commits_after_tag = o
      end
      opts.on("-f", "--fav_repos", "Show fav repos only") do |o|
        @cmd.opt_fav_repos = o
      end
      opts.on("-a", "--show_stashes", "Show stashes too") do |o|
        @cmd.opt_show_stashes = o
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
    current_dir = File.dirname(__FILE__)
    if !File.exists? File.join current_dir, 'settings.yml'
      puts red "Configure me first!:"
      puts red "cp settings.yml.example settings.yml"
      puts red "vim settings.yml"
      exit
    end
  end

  def setup_home_variable!
    current_dir = File.dirname(__FILE__)
    begin
      cnf = YAML::load(File.open(File.join current_dir, 'settings.yml'))
      @cmd.setting_repos_home = cnf['settings']['your_home_of_all_git_repos']
      @cmd.setting_fav_repos = cnf['settings']['fav_repos'] || []
      @cmd.setting_excluded_repos = cnf['settings']['excluded_repos'] || []
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

