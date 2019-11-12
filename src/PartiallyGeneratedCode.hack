/*
 *  Copyright (c) 2015-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the MIT license found in the
 *  LICENSE file in the root directory of this source tree.
 *
 */

namespace Facebook\HackCodegen;

use namespace HH\Lib\{C, Str};

/**
 * Manage partially generated code.  The main operation is to merge existing
 * code (that probably has some handwritten code) with generated code.
 */
final class PartiallyGeneratedCode {

  private string $code;

  private static string $manualBegin = '/* BEGIN MANUAL SECTION %s */';
  private static string $manualEnd = '/* END MANUAL SECTION */';

  public function __construct(string $code) {
    $this->code = $code;
  }

  public static function getBeginManualSection(string $id): string {
    return \sprintf('/* BEGIN MANUAL SECTION %s */', $id);
  }

  private static function getBeginManualSectionRegex(string $regex): string {
    // this needs to be kept in sync with getBeginManualSection.
    return \sprintf('|/\* BEGIN MANUAL SECTION %s \*/|', $regex);
  }

  public static function getEndManualSection(): string {
    return '/* END MANUAL SECTION */';
  }

  public static function containsManualSection(string $code): bool {
    return \strpos($code, self::getEndManualSection()) !== false;
  }

  /**
   * Merge the code with the existing code. The manual sections of
   * the existing code will be merged into the corresponding sections
   * of the new code.
   *
   * If rekeys is specified, we will attempt to pull code from sections
   * with different names, as specified by the mapping.
   */
  public function merge(
    string $existing_code,
    ?KeyedContainer<string, Traversable<string>> $rekeys = null,
  ): string {
    $merged = varray[];
    $existing = $this->extractManualCode($existing_code);
    $generated = $this->iterateCodeSections($this->code);
    foreach ($generated as $section) {
      list($id, $chunk) = $section;
      if ($id === null) {
        // Autogenerated section, add it as it is
        $merged[] = $chunk;
      } else {
        if (C\contains_key($existing, $id)) {
          // This manual section was present in the existing code, so insert it
          $merged[] = $existing[$id];
        } else {
          $content = vec[];
          if ($rekeys !== null) {
            if (C\contains_key($rekeys, $id)) {
              foreach ($rekeys[$id] as $old_id) {
                if (C\contains_key($existing, $old_id)) {
                  $content[] = $existing[$old_id];
                }
              }
            }
          }
          if ($content) {
            $merged[] = Str\join($content, "\n\n");
          } else {
            // This manual section is new, so insert inside it the chunk from
            // the generated code (e.g. the generated code can have a comment
            // saying what that manual section should be used for)
            $merged[] = $chunk;
          }
        }
      }
    }
    return Str\join(\array_filter($merged), "\n");
  }

  /**
   * Extract manually generated code and returns a map of ids to chunks of code
   */
  private function extractManualCode(string $code): dict<string, string> {
    $manual = dict[];
    foreach ($this->iterateCodeSections($code) as $section) {
      list($id, $chunk) = $section;
      if ($id !== null) {
        $manual[$id] = $chunk;
      }
    }
    return $manual;
  }

  /**
   * Extract the generated code and returns it as a string.
   */
  public function extractGeneratedCode(): string {
    $generated = varray[];
    foreach ($this->iterateCodeSections($this->code) as $section) {
      list($id, $chunk) = $section;
      if ($id === null) {
        $generated[] = $chunk;
      }
    }
    return Str\join($generated, "\n");
  }

  /**
   * Validate the manual sections and throws PartiallyGeneratedCodeException
   * if there are any errors (e.g. unfinished manual section, nested
   * manual sections, duplicated ids, etc)
   */
  public function assertValidManualSections(): void {
    foreach ($this->iterateCodeSections($this->code) as $_section) {
    }
  }

  /**
   * Iterates through the code yielding tuples of ($id, $chunk), where
   * $id is the id of the manual section or null if it's an auto-generated
   * section, and chunk is the code belonging to that section.
   * The lines containing begin/end of manual section belong to the
   * autogenerated sections.
   */
  private function iterateCodeSections(
    string $code,
  ): \Generator<int, (?string, string), void> {
    // Regular expression to match the beginning of a manual section
    $begin = self::getBeginManualSectionRegex('(.*)');
    $valid_begin = self::getBeginManualSectionRegex('([A-Za-z0-9:_]+)');

    $seen_ids = keyset[];
    $current_id = null;
    $chunk = varray[];
    $lines = \explode("\n", $code);
    foreach ($lines as $line) {
      if (\strpos($line, self::$manualEnd) !== false) {
        yield tuple($current_id, Str\join($chunk, "\n"));
        $chunk = varray[$line];
        $current_id = null;

      } else if (\preg_match($begin, $line) === 1) {
        if ($current_id !== null) {
          throw new PartiallyGeneratedCodeException(
            "The manual section ".$current_id." was open before ".
            "the previous one was closed",
          );
        }
        if (!\preg_match($valid_begin, $line)) {
          throw
            new PartiallyGeneratedCodeException("Invalid id specified: ".$line);
        }

        $chunk[] = $line;
        yield tuple(null, Str\join($chunk, "\n"));
        $chunk = varray[];
        $current_id = \trim(\preg_replace($begin, '\\1', $line));

        if (C\contains($seen_ids, $current_id)) {
          throw new PartiallyGeneratedCodeException(
            "Duplicate manual section id: ".$current_id,
          );
        }
        $seen_ids[] = $current_id;
      } else {
        $chunk[] = $line;
      }
    }
    if ($current_id !== null) {
      throw new PartiallyGeneratedCodeException(
        "The manual section ".$current_id." was not closed at the end of code",
      );
    }
    if ($code !== '') {
      yield tuple(null, Str\join($chunk, "\n"));
    }
  }
}

final class PartiallyGeneratedCodeException extends \Exception {
}
