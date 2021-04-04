#!/usr/bin/env python3

import collections
import json
import os
import subprocess


def run(cmd):
  proc = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE)
  output = proc.stdout.read()
  print(output.decode('utf8'), end='')

def main():
  json_data=open('./priv/schema.json')
  data = json.load(json_data, object_pairs_hook=collections.OrderedDict)

  exclude = {"malfunction",
             "table",
             "service",
             "subscriber",
             "test"
  }

  lib_path = "./c_src/lib"
  h_cog_file = os.path.join(lib_path, "wm_entity.h.cog")
  c_cog_file = os.path.join(lib_path, "wm_entity.cpp.cog")

  for entity in data:
    if entity in exclude:
        continue
    cmd = "cog.py -U -z -d -e -c -D WM_ENTITY_NAME=%s" % entity
    h_out_file = os.path.join(lib_path, "wm_%s.h" % entity)
    c_out_file = os.path.join(lib_path, "wm_%s.cpp" % entity)
    run("%s -o %s %s" % (cmd, h_out_file, h_cog_file))
    run("%s -o %s %s" % (cmd, c_out_file, c_cog_file))


if __name__ == "__main__":
  main()

