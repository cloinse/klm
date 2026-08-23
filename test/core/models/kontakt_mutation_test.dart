import 'package:flutter_test/flutter_test.dart';
import 'package:kontakt_library_manager/core/models/kontakt_library.dart';
import 'package:kontakt_library_manager/core/models/kontakt_mutation.dart';

void main() {
  const library = KontaktLibrary(
    id: 'test-library',
    name: 'Test Library',
    regKey: 'Test Library',
    snpid: 'ABC',
    contentPath: '/Samples/Test Library',
  );

  test('remove request cannot carry a content folder or target paths', () {
    final payload = KontaktMutationRequest.remove(library).payload;

    expect(payload['operation'], 'remove');
    expect(payload['name'], 'Test Library');
    expect(payload['regKey'], 'Test Library');
    expect(payload, isNot(contains('contentPath')));
    expect(payload, isNot(contains('target')));
    expect(payload, isNot(contains('paths')));
  });

  test('relocate request carries the content path but no writable target', () {
    final payload = KontaktMutationRequest.relocate(
      library,
      '/Volumes/Samples/Test Library',
    ).payload;

    expect(payload['operation'], 'relocate');
    expect(payload['contentPath'], '/Volumes/Samples/Test Library');
    expect(payload, isNot(contains('target')));
    expect(payload, isNot(contains('paths')));
  });

  test('batch request wraps multiple validated operations', () {
    final remove = KontaktMutationRequest.remove(library).payload;
    final payload = KontaktMutationRequest.batch([remove, remove]).payload;

    expect(payload['version'], 1);
    expect(payload, isNot(contains('operation')));
    expect(payload['operations'], hasLength(2));
  });

  test('batch response returns every mutation result', () {
    final results = KontaktMutationResult.listFromMap({
      'operation': 'batch',
      'results': [
        {
          'operation': 'remove',
          'libraryName': 'Alpha',
          'changedPaths': ['/alpha.xml'],
        },
        {
          'operation': 'remove',
          'libraryName': 'Beta',
          'changedPaths': ['/beta.xml'],
        },
      ],
    });

    expect(results.map((result) => result.libraryName), ['Alpha', 'Beta']);
    expect(
      results.every((result) => result.operation == KontaktMutationType.remove),
      isTrue,
    );
  });
}
