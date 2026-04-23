#!/usr/bin/env ruby

# Copyright 2024 Pim Snel <post@pimsnel.com>
# License: MIT

require 'json'
require 'pp'
require 'yaml'

def isLiteralExpression(val, key)
  if val.key? key and val[key].instance_of? Hash and val[key].key? "_type" and val[key]['_type'] == 'literalExpression'
    true
  else
    false
  end
end

def getValFor(val, key)
  if isLiteralExpression(val, key)
    val[key]['text']
  elsif val.key? key
    val[key]
  else
    ""
  end
end

def parseVal(val)
  val['example'] = getValFor(val, 'example')
  val['default'] = getValFor(val, 'default')

  val
end

in_file_conf = File.read("./config.yaml")
config = YAML.load(in_file_conf)

if not ENV['NIXOS_RELEASE']
  ENV['NIXOS_RELEASE'] = "unstable"
elsif ENV['NIXOS_RELEASE'] == "stable"
  ENV['NIXOS_RELEASE'] = config['params']['release_current_stable'].sub('release-', '')
end

# Map release name to nixpkgs branch
release = ENV['NIXOS_RELEASE']
if release == "unstable"
  nixpkgs_branch = "nixos-unstable"
else
  nixpkgs_branch = "nixos-#{release}"
end

puts "Cleanup and Building NixOS options from #{release} (nixpkgs branch: #{nixpkgs_branch})"

`rm -Rf result`

nix_expr = <<~NIX
  let
    flake = builtins.getFlake "github:NixOS/nixpkgs/#{nixpkgs_branch}";
    pkgs = import flake { system = "x86_64-linux"; };
    eval = import (flake + "/nixos") { configuration = {}; };
  in (pkgs.nixosOptionsDoc { options = eval.options; }).optionsJSON
NIX

system("nix build --impure --expr '#{nix_expr}' --no-write-lock-file")

if !File.exist?("./result/share/doc/nixos/options.json")
  STDERR.puts "ERROR: Failed to build options JSON for #{release}"
  exit 1
end

in_file = File.read("./result/share/doc/nixos/options.json")
parsed = JSON.parse(in_file)

options_arr = []
parsed.each do | name, val |

  next if name == '_module.args'

  val['title'] = name
  val = parseVal(val)

  options_arr << val
end

outobj = {}
time = Time.new
outobj["last_update"] = time.utc.strftime("%B %d, %Y at %k:%M UTC")
outobj["options"] = options_arr

filename = "static/data/options-release-#{release}.json"

File.open(filename,"w") do |f|
    f.write(outobj.to_json)
end

puts "Finished parsing NixOS options for #{release}. #{options_arr.length} options written to #{filename}"
