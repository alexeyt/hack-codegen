#!/usr/bin/env hhvm
/*
 *  Copyright (c) 2015-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the MIT license found in the
 *  LICENSE file in the root directory of this source tree.
 *
 */

namespace Facebook\HackCodegen;

use namespace HH\Lib\{C, Vec};

final class DormCodegenCLI extends \Facebook\CLILib\CLIWithRequiredArguments {
  <<__Override>>
  public static function getHelpTextForRequiredArguments(): vec<string> {
    return vec['FILENAME'];
  }

  <<__Override>>
  protected function getSupportedOptions(
  ): vec<\Facebook\CLILib\CLIOptions\CLIOption> {
    return vec[];
  }

  <<__Override>>
  public async function mainAsync(): Awaitable<int> {
    $fname = C\firstx($this->getArguments());
    if (!\file_exists($fname)) {
      await $this->getStderr()
        ->writeAsync("  File doesn't exist: ".$fname."\n\n");
      return 1;
    }

    $classes = \get_declared_classes();
    require_once($fname);
    $new_classes = Vec\diff(\get_declared_classes(), $classes);


    foreach ($new_classes as $class_name) {
      $ref = new \ReflectionClass($class_name);
      if ($ref->isAbstract()) {
        continue;
      }
      $instance = $ref->newInstance() as DormSchema;
      /* HHAST_IGNORE_ERROR[DontAwaitInALoop] */
      await $this->getStdout()
        ->writeAsync("Generating code for ".$class_name."\n");
      (new CodegenDorm($instance))->generate();
      (new CodegenMutator($instance))->generate();
    }

    return 0;
  }
}

<<__EntryPoint>>
async function dorm_codegen_cli_main_async(): Awaitable<noreturn> {
  (() ==> {
    // HHAST-generated to avoid pseudomain local leaks
    require_once(__DIR__.'/../../vendor/hh_autoload.hh');
  })();
  $exit_code = await DormCodegenCLI::runAsync();
  exit($exit_code);
}