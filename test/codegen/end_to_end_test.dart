// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// And end-to-end test that generates code and checks that the output matches
/// the code in `static_test.dart`. Techincally we could run the result in an
/// isolate, but instead we decided to split that up in two tests. This test
/// ensures that we generate the code as it was written in static_test, and
/// separately static_test ensures that the smoke.static library behaves as
/// expected.
@TestOn('vm')
library smoke.test.codegen.end_to_end_test;

import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:smoke/codegen/generator.dart';
import 'package:smoke/codegen/recorder.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as path;

import 'testing_resolver_utils.dart' show initAnalyzer;

void main([List<String> args]) {
  final updateStaticTest =
      args != null && args.length > 0 && args[0] == '--update_static_test';

  test('static_test is up to date', () {
    var scriptPath = path.fromUri(Platform.script);
    var testDir = path.dirname(path.dirname(scriptPath));
    var commonPath = path.join(testDir, 'common.dart');
    var testCode = new File('$commonPath').readAsStringSync();
    var lib = initAnalyzer({'common.dart': testCode}).libraryFor('common.dart');
    var generator = new SmokeCodeGenerator();
    var recorder = new Recorder(generator, _resolveImportUrl);

    lookupMember(String className, String memberName, bool recursive) {
      recorder.lookupMember(lib.getType(className), memberName,
          recursive: recursive, includeAccessors: false);
    }

    runQuery(String className, QueryOptions options) {
      recorder.runQuery(lib.getType(className), options,
          includeAccessors: false);
    }

    // Record all getters and setters we use in the tests.
    ['i', 'j', 'j2', 'inc0', 'inc1', 'inc2', 'toString']
        .forEach(generator.addGetter);
    ['i', 'j2'].forEach(generator.addSetter);

    // Record static methods used in the tests
    recorder.addStaticMethod(lib.getType('A'), 'staticInc');

    // Record symbol convertions.
    generator.addSymbol('i');

    /// Record all parent-class relations that we explicitly request.
    ['AnnotB', 'A', 'B', 'D', 'H']
        .forEach((className) => recorder.lookupParent(lib.getType(className)));

    // Record members for which we implicitly request their declaration in
    // has-getter and has-setter tests.
    lookupMember('A', 'i', true);
    lookupMember('A', 'j2', true);
    lookupMember('A', 'inc2', true);
    lookupMember('B', 'a', true);
    lookupMember('B', 'f', true);
    lookupMember('D', 'i', true);
    lookupMember('E', 'y', true);

    // Record also lookups for non-exisiting members.
    lookupMember('B', 'i', true);
    lookupMember('E', 'x', true);
    lookupMember('E', 'z', true);

    // Record members for which we explicitly request their declaration.
    lookupMember('B', 'a', false);
    lookupMember('B', 'w', false);
    lookupMember('A', 'inc1', false);
    lookupMember('F', 'staticMethod', false);
    lookupMember('G', 'b', false);
    lookupMember('G', 'd', false);

    // Lookups from no-such-method test.
    lookupMember('A', 'noSuchMethod', true);
    lookupMember('E', 'noSuchMethod', true);
    lookupMember('E2', 'noSuchMethod', true);

    // Lookups from has-instance-method and has-static-method tests.
    lookupMember('A', 'inc0', true);
    lookupMember('A', 'inc3', true);
    lookupMember('C', 'inc', true);
    lookupMember('D', 'inc', true);
    lookupMember('D', 'inc0', true);
    lookupMember('F', 'staticMethod', true);
    lookupMember('F2', 'staticMethod', true);

    // Record all queries done by the test.
    runQuery('A', new QueryOptions());
    runQuery('D', new QueryOptions(includeInherited: true));

    var vars = lib.definingCompilationUnit.topLevelVariables;
    expect(vars[0].name, 'a1');
    expect(vars[1].name, 'a2');

    runQuery(
        'H',
        new QueryOptions(
            includeInherited: true,
            withAnnotations: [vars[0], vars[1], lib.getType('Annot')]));

    runQuery(
        'K',
        new QueryOptions(
            includeInherited: true, withAnnotations: [lib.getType('AnnotC')]));

    runQuery('L', new QueryOptions(includeMethods: true));
    runQuery(
        'L2', new QueryOptions(includeInherited: true, includeMethods: true));

    var code = _createEntrypoint(generator);
    var staticTestFile = new File(path.join(testDir, 'static_test.dart'));
    var existingCode = staticTestFile.readAsStringSync();
    if (!updateStaticTest) {
      expect(code, existingCode);
    } else if (code == existingCode) {
      print('static_test.dart is already up to date');
    } else {
      staticTestFile.writeAsStringSync(code);
      print('static_test.dart has been updated.');
    }
  }, skip: 'https://github.com/dart-lang/smoke/issues/26');
}

String _createEntrypoint(SmokeCodeGenerator generator) {
  var sb = new StringBuffer()
    ..writeln('/// ---- AUTOGENERATED: DO NOT EDIT THIS FILE --------------')
    ..writeln('/// To update this test file, call:')
    ..writeln('/// > dart codegen/end_to_end_test.dart --update_static_test')
    ..writeln('/// --------------------------------------------------------')
    ..writeln('\nlibrary smoke.test.static_test;\n')
    ..writeln("import 'package:unittest/unittest.dart';");

  generator.writeImports(sb);
  sb.writeln("import 'common.dart' as common show main;\n");
  generator.writeTopLevelDeclarations(sb);
  sb.write('\nfinal configuration = ');
  generator.writeStaticConfiguration(sb, 0);

  sb
    ..writeln(';\n')
    ..writeln('main() {')
    ..writeln('  setUp(() => useGeneratedCode(configuration));')
    ..writeln('  common.main();')
    ..writeln('}');
  return sb.toString();
}

String _resolveImportUrl(LibraryElement lib) {
  if (lib.isDartCore) return 'dart:core';
  if (lib.displayName == 'smoke.test.common') return 'common.dart';
  return 'unknown.dart';
}
