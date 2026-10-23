"""Exercise cache control flow without Xcode or a simulator; real builds run in Actions."""
import base64
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
NAMES = ['lock', 'reply', 'toolCall', 'toolOutput', 'reply-dark']
PNG = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aSioAAAAASUVORK5CYII=')


class CacheGuards(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for folder in ['scripts', 'bin', 'Tests/Fixtures']:
            (self.root / folder).mkdir(parents=True)
        for name in ['ci-screenshots.sh', 'ci-regressions.sh']:
            shutil.copyfile(REPO / 'scripts' / name, self.root / 'scripts' / name)
        self.calls = self.root / 'compiler-calls'
        fake = self.root / 'bin/xcrun'
        fake.write_text('#!/bin/bash\nprintf "called\\n" >> "$GUARD_CALLS"\nexit 37\n')
        fake.chmod(0o755)
        self.env = {**os.environ, 'PATH': f'{self.root / "bin"}:{os.environ["PATH"]}',
                    'GUARD_CALLS': str(self.calls), 'GITHUB_STEP_SUMMARY': str(self.root / 'summary')}

    def run_script(self, script, **env):
        return subprocess.run(['bash', str(self.root / 'scripts' / script)],
                              env={**self.env, **env}, capture_output=True, text=True, timeout=15)

    def images(self):
        folder = self.root / '.ci-cache/screenshots/images'
        folder.mkdir(parents=True)
        for name in NAMES:
            (folder / f'{name}.png').write_bytes(PNG)
        return folder

    def test_exact_images_are_reused(self):
        self.images()
        result = self.run_script('ci-screenshots.sh', CI_SCREENSHOTS_CACHE_HIT='true')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.calls.exists())
        self.assertEqual(len(list((self.root / 'build/screenshots').glob('*.png'))), 5)
        self.assertIn('no new simulator', result.stdout)

    def test_partial_image_cache_requires_render(self):
        images = self.images()
        result = self.run_script('ci-screenshots.sh', CI_SCREENSHOTS_CACHE_HIT='false')
        self.assertNotEqual(result.returncode, 0)  # Deliberately unavailable Xcode stub.
        self.assertTrue(self.calls.exists())
        self.assertFalse(images.exists())
        self.assertEqual(list((self.root / 'build/screenshots').glob('*.png')), [])

    def test_incomplete_exact_image_cache_requires_render(self):
        (self.images() / 'reply.png').write_bytes(b'broken')
        result = self.run_script('ci-screenshots.sh', CI_SCREENSHOTS_CACHE_HIT='true')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.calls.exists())

    def test_cached_regressions_still_execute_each_time(self):
        # The stand-in only checks shell control flow, not the Swift assertions.
        (self.root / 'Tests/Fixtures/server.py').write_text(
            'from pathlib import Path\nimport os,sys,time\nPath(sys.argv[1]).write_text(str(os.getpid()))\ntime.sleep(30)\n')
        cache = self.root / '.ci-cache/regressions'
        cache.mkdir(parents=True)
        binary = cache / 'regressions'
        binary.write_text('#!/bin/bash\nprintf "%s\\n" "$1" >> "$GUARD_EXECUTIONS"\n')
        binary.chmod(0o755)
        log = self.root / 'executions'
        for _ in range(2):
            result = self.run_script('ci-regressions.sh', CI_REGRESSION_CACHE_HIT='true',
                                     CI_REGRESSION_CACHE_DIR=str(cache), GUARD_EXECUTIONS=str(log))
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(set(log.read_text().splitlines())), 2)
        self.assertFalse(self.calls.exists())
        result = self.run_script('ci-regressions.sh', CI_REGRESSION_CACHE_HIT='false',
                                 CI_REGRESSION_CACHE_DIR=str(cache), GUARD_EXECUTIONS=str(log))
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.calls.exists())
        self.assertEqual(len(log.read_text().splitlines()), 2)


if __name__ == '__main__':
    unittest.main()
