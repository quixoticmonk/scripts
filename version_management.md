# Python Multi-Version Library Management Strategy

## Overview

This document outlines strategies for managing a Python library that supports both Python 3.7.16 and Python 3.11, specifically designed for AWS Glue external datasource support with strict runtime dependencies.

## Table of Contents

1. [Version-Based Branching Strategy](#version-based-branching-strategy)
2. [Conditional Dependencies Management](#conditional-dependencies-management)
3. [Feature Detection Pattern](#feature-detection-pattern)
4. [CI/CD Strategy with GitHub Actions](#cicd-strategy-with-github-actions)
5. [Release Management Strategies](#release-management-strategies)
6. [Project Structure Recommendations](#project-structure-recommendations)
7. [Documentation Strategy](#documentation-strategy)
8. [AWS Glue Specific Considerations](#aws-glue-specific-considerations)
9. [Implementation Examples](#implementation-examples)

---

## Version-Based Branching Strategy

### Branch Structure

```
main (Python 3.7 compatible - stable)
├── release/5.0 (Python 3.11+ features)
├── feature/new-py37-feature
└── hotfix/critical-fix
```

### Versioning Scheme

- **Python 3.7**: `v1.x.x` (Main branch - stable)
- **Python 3.11+**: `v2.x.x` (Release/5.0 branch - Glue 5.0 features)

### Branch Management Workflow

1. **Main Development**: All stable features and Python 3.7 compatibility maintained in `main` branch
2. **Modern Features**: Python 3.11+ specific features developed in `release/5.0` branch
3. **Feature Development**: 
   - Python 3.7 compatible features: branch from `main`
   - Python 3.11+ features: branch from `release/5.0`
4. **Release Process**: 
   - Tag releases from `main` for v1.x.x (Python 3.7)
   - Tag releases from `release/5.0` for v2.x.x (Python 3.11+ / Glue 5.0)
   - Maintain separate CHANGELOG files for each version

### Pros and Cons

**Pros:**
- Stable main branch for production use
- Clear separation between stable and experimental features
- Python 3.7 remains the primary supported version
- Easy rollback to stable versions

**Cons:**
- Modern features require branch switching
- Potential merge conflicts between branches
- Need to maintain feature parity documentation

---

## Conditional Dependencies Management

### Using setup.py

```python
import sys
from setuptools import setup, find_packages

# Base dependencies that work across all Python versions
base_requirements = [
    "boto3>=1.20.0,<2.0.0",
    "botocore>=1.23.0,<2.0.0",
    "requests>=2.25.0",
]

# Python version specific dependencies
python_37_requirements = [
    "pandas>=1.3.0,<2.0.0",
    "numpy>=1.19.0,<1.22.0",
    "typing-extensions>=3.10.0",  # Backport newer typing features
]

python_311_requirements = [
    "pandas>=2.0.0",
    "numpy>=1.24.0",
    "polars>=0.18.0",  # Modern data processing library
]

# Determine requirements based on Python version
if sys.version_info >= (3, 11):
    install_requires = base_requirements + python_311_requirements
elif sys.version_info >= (3, 7):
    install_requires = base_requirements + python_37_requirements
else:
    raise RuntimeError("Python 3.7+ is required")

setup(
    name="aws-glue-datasource-lib",
    python_requires=">=3.7,<4.0",
    install_requires=install_requires,
    extras_require={
        "dev": [
            "pytest>=6.0.0",
            "black>=22.0.0",
            "mypy>=0.950",
        ],
        "py311-extras": [
            "advanced-feature-lib>=1.0.0; python_version>='3.11'",
        ],
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Programming Language :: Python :: 3.7",
        "Programming Language :: Python :: 3.11",
        "Topic :: Database",
        "Topic :: Software Development :: Libraries :: Python Modules",
    ],
)
```

### Alternative: requirements.txt Approach

For simpler dependency management, you can use separate requirements files:

```
# requirements/base.txt
boto3>=1.20.0,<2.0.0
botocore>=1.23.0,<2.0.0
requests>=2.25.0

# requirements/py37.txt
-r base.txt
pandas>=1.3.0,<2.0.0
numpy>=1.19.0,<1.22.0
typing-extensions>=3.10.0

# requirements/py311.txt  
-r base.txt
pandas>=2.0.0
numpy>=1.24.0
polars>=0.18.0
```

Then in your setup.py:

```python
import sys
from setuptools import setup, find_packages

def read_requirements(filename):
    with open(filename, 'r') as f:
        return [line.strip() for line in f if line.strip() and not line.startswith('#') and not line.startswith('-r')]

# Determine requirements file based on Python version
if sys.version_info >= (3, 11):
    requirements_file = 'requirements/py311.txt'
elif sys.version_info >= (3, 7):
    requirements_file = 'requirements/py37.txt'
else:
    raise RuntimeError("Python 3.7+ is required")

setup(
    name="aws-glue-datasource-lib",
    python_requires=">=3.7,<4.0",
    install_requires=read_requirements(requirements_file),
    # ... rest of setup configuration
)
```

---

## Feature Detection Pattern

### Runtime Version Detection

```python
# src/glue_lib/compat.py
import sys
from typing import TYPE_CHECKING, Any, Dict, Optional, Union

# Version flags
PYTHON_37 = sys.version_info[:2] == (3, 7)
PYTHON_311_PLUS = sys.version_info >= (3, 11)
PYTHON_VERSION = sys.version_info[:2]

# Feature availability flags
HAS_STRUCTURAL_PATTERN_MATCHING = PYTHON_311_PLUS
HAS_UNION_OPERATOR = PYTHON_311_PLUS
HAS_ENHANCED_ERROR_LOCATIONS = PYTHON_311_PLUS

# Type compatibility
if PYTHON_311_PLUS:
    from types import UnionType
    JSONType = dict[str, Any] | list[Any] | str | int | float | bool | None
else:
    from typing import Union
    UnionType = type(Union[str, int])  # Fallback
    JSONType = Union[Dict[str, Any], list, str, int, float, bool, None]

# Import compatibility
try:
    from functools import cached_property
except ImportError:
    # Python < 3.8 fallback
    from functools import lru_cache
    def cached_property(func):
        return property(lru_cache()(func))
```

### Conditional Feature Implementation

```python
# src/glue_lib/core/connector.py
from typing import TYPE_CHECKING, Any, Dict, List, Optional
from .compat import PYTHON_311_PLUS, JSONType

if PYTHON_311_PLUS:
    from .modern_features import AdvancedDataProcessor, ModernGlueConnector
else:
    from .legacy_features import BasicDataProcessor, LegacyGlueConnector

class GlueDataSourceConnector:
    """Main connector class with version-specific implementations."""
    
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        
        # Initialize appropriate processor based on Python version
        if PYTHON_311_PLUS:
            self._processor = AdvancedDataProcessor(config)
            self._connector = ModernGlueConnector(config)
        else:
            self._processor = BasicDataProcessor(config)
            self._connector = LegacyGlueConnector(config)
    
    def process_data(self, data: JSONType) -> JSONType:
        """Process data using version-appropriate methods."""
        if PYTHON_311_PLUS:
            return self._process_modern(data)
        else:
            return self._process_legacy(data)
    
    def _process_modern(self, data: JSONType) -> JSONType:
        """Python 3.11+ specific processing with pattern matching."""
        match data:
            case {"type": "table", "data": table_data}:
                return self._processor.process_table(table_data)
            case {"type": "stream", "data": stream_data}:
                return self._processor.process_stream(stream_data)
            case _:
                return self._processor.process_generic(data)
    
    def _process_legacy(self, data: JSONType) -> JSONType:
        """Python 3.7 compatible processing."""
        if isinstance(data, dict):
            data_type = data.get("type")
            if data_type == "table":
                return self._processor.process_table(data["data"])
            elif data_type == "stream":
                return self._processor.process_stream(data["data"])
        
        return self._processor.process_generic(data)
```

---

## CI/CD Strategy with GitHub Actions

### Multi-Version Testing Workflow

```yaml
# .github/workflows/test.yml
name: Test Suite

on:
  push:
    branches: [ main, release/5.0 ]
  pull_request:
    branches: [ main, release/5.0 ]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        python-version: ["3.7.16", "3.11"]
        include:
          - python-version: "3.7.16"
            toxenv: py37
            branch-constraint: main
          - python-version: "3.11"
            toxenv: py311
            branch-constraint: release/5.0

    steps:
    - name: Checkout code
      uses: actions/checkout@v4
      
    - name: Set up Python ${{ matrix.python-version }}
      uses: actions/setup-python@v4
      with:
        python-version: ${{ matrix.python-version }}
        
    - name: Cache pip dependencies
      uses: actions/cache@v3
      with:
        path: ~/.cache/pip
        key: ${{ runner.os }}-pip-${{ matrix.python-version }}-${{ hashFiles('**/requirements*.txt', 'setup.py') }}
        
    - name: Install dependencies
      run: |
        python -m pip install --upgrade pip
        pip install tox tox-gh-actions
        
    - name: Install package
      run: |
        pip install -e .
        if [[ "${{ matrix.python-version }}" == "3.11" ]]; then
          pip install -e .[py311-extras]
        fi
        
    - name: Run tests with tox
      run: tox -e ${{ matrix.toxenv }}
      
    - name: Upload coverage reports
      uses: codecov/codecov-action@v3
      with:
        file: ./coverage.xml
        flags: ${{ matrix.toxenv }}
```

### Release Workflow

```yaml
# .github/workflows/release.yml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
      
    - name: Determine Python version from tag
      id: version
      run: |
        if [[ ${{ github.ref }} == refs/tags/v1.* ]]; then
          echo "python_version=3.7.16" >> $GITHUB_OUTPUT
          echo "package_suffix=-py37" >> $GITHUB_OUTPUT
        elif [[ ${{ github.ref }} == refs/tags/v2.* ]]; then
          echo "python_version=3.11" >> $GITHUB_OUTPUT
          echo "package_suffix=" >> $GITHUB_OUTPUT
        fi
        
    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: ${{ steps.version.outputs.python_version }}
        
    - name: Build package
      run: |
        pip install build
        python -m build
        
    - name: Publish to PyPI
      uses: pypa/gh-action-pypi-publish@release/v1
      with:
        password: ${{ secrets.PYPI_API_TOKEN }}
```

### Tox Configuration

```ini
# tox.ini
[tox]
envlist = py37, py311, lint, type-check
isolated_build = True

[testenv]
deps = 
    pytest>=6.0.0
    pytest-cov>=2.10.0
    pytest-mock>=3.6.0
commands = 
    pytest {posargs} --cov=glue_lib --cov-report=xml --cov-report=term-missing

[testenv:py37]
basepython = python3.7
deps = 
    {[testenv]deps}
    pandas>=1.3.0,<2.0.0
    numpy>=1.19.0,<1.22.0

[testenv:py311]
basepython = python3.11
deps = 
    {[testenv]deps}
    pandas>=2.0.0
    numpy>=1.24.0
    polars>=0.18.0

[testenv:lint]
deps = 
    black>=22.0.0
    flake8>=4.0.0
    isort>=5.10.0
commands = 
    black --check src/ tests/
    flake8 src/ tests/
    isort --check-only src/ tests/

[testenv:type-check]
deps = 
    mypy>=0.950
    types-requests
commands = 
    mypy src/
```

---

## Release Management Strategies

### Strategy 1: Dual Package Distribution

**Separate Packages:**
- `aws-glue-datasource-lib` (Python 3.7 - main package)
- `aws-glue-datasource-lib-modern` (Python 3.11+)

**Pros:**
- Clear separation for users
- Independent versioning
- No compatibility constraints

**Cons:**
- Maintenance overhead
- User confusion
- Package discovery issues

### Strategy 2: Single Package with Version Constraints (Recommended)

**Single Package:** `aws-glue-datasource-lib`

**Version Strategy:**
```
v1.x.x - Python 3.7 compatible (main branch - stable)
v2.x.x - Python 3.11+ with Glue 5.0 features (release/5.0 branch)
```

**Release Process:**
1. Develop stable features in `main` branch (Python 3.7 compatible)
2. Develop Glue 5.0 features in `release/5.0` branch (Python 3.11+)
3. Release v1.x.x from `main` (stable releases)
4. Release v2.x.x from `release/5.0` (Glue 5.0 features)

### Semantic Versioning Guidelines

```
MAJOR.MINOR.PATCH

MAJOR: Python version compatibility changes
MINOR: New features (backward compatible within Python version)
PATCH: Bug fixes and small improvements
```

**Examples:**
- `v1.0.0` - Stable Python 3.7 release (main branch)
- `v1.1.0` - New feature for Python 3.7
- `v1.1.1` - Bug fix for Python 3.7
- `v2.0.0` - Python 3.11+ with Glue 5.0 features
- `v2.1.0` - New Python 3.11+ / Glue 5.0 features

---

## Project Structure Recommendations

```
aws-glue-datasource-lib/
├── .github/
│   ├── workflows/
│   │   ├── test.yml
│   │   ├── release.yml
│   │   └── lint.yml
│   └── ISSUE_TEMPLATE/
├── src/
│   └── glue_lib/
│       ├── __init__.py
│       ├── _version.py          # Auto-generated version
│       ├── compat.py            # Compatibility layer
│       ├── core/                # Core functionality
│       │   ├── __init__.py
│       │   ├── connector.py
│       │   ├── config.py
│       │   └── exceptions.py
│       ├── datasources/         # Data source implementations
│       │   ├── __init__.py
│       │   ├── base.py
│       │   ├── s3.py
│       │   ├── rds.py
│       │   └── custom.py
│       ├── modern_features/     # Python 3.11+ specific (release/5.0)
│       │   ├── __init__.py
│       │   ├── advanced_processor.py
│       │   └── pattern_matching.py
│       └── legacy_features/     # Python 3.7 compatible (main)
│           ├── __init__.py
│           ├── basic_processor.py
│           └── compatibility.py
├── tests/
│   ├── __init__.py
│   ├── conftest.py
│   ├── unit/
│   │   ├── test_core/
│   │   ├── test_datasources/
│   │   └── test_compatibility/
│   ├── integration/
│   │   ├── test_py37_specific/
│   │   └── test_py311_specific/
│   └── fixtures/
├── docs/
│   ├── installation.md
│   ├── compatibility-matrix.md
│   ├── migration-guide.md
│   └── api-reference/
├── requirements/
│   ├── base.txt
│   ├── py37.txt
│   ├── py311.txt
│   └── dev.txt
├── setup.py
├── tox.ini
├── README.md
├── CHANGELOG.md
├── LICENSE
└── .gitignore
```

---

## Documentation Strategy

### Installation Documentation

```markdown
# Installation Guide

## Python 3.7 (Stable - Recommended for Production)

```bash
pip install "aws-glue-datasource-lib>=1.0.0,<2.0.0"
```

## Python 3.11+ (Glue 5.0 Features)

```bash
pip install aws-glue-datasource-lib>=2.0.0
```

## Version Compatibility Matrix

| Python Version | Library Version | Features | Branch | AWS Glue |
|----------------|-----------------|----------|---------|----------|
| 3.7.16         | 1.x.x          | Core functionality, stable features | main | Glue 2.0 |
| 3.11+          | 2.x.x          | All features, Glue 5.0 processing, pattern matching | release/5.0 | Glue 5.0 |
```

### Migration Guide

```markdown
# Migration Guide: Python 3.7 to 3.11 (Glue 2.0 to Glue 5.0)

## Overview
This guide helps you migrate from the Python 3.7 stable version (v1.x.x) to the Python 3.11+ Glue 5.0 version (v2.x.x).

## Breaking Changes

### 1. Import Changes
```python
# Old (v1.x.x - Python 3.7 / Glue 2.0)
from glue_lib.legacy_features import BasicProcessor

# New (v2.x.x - Python 3.11+ / Glue 5.0)
from glue_lib.modern_features import AdvancedProcessor
```

### 2. Configuration Changes
```python
# Old configuration (v1.x.x)
config = {
    "processor_type": "basic",
    "compatibility_mode": True,
    "glue_version": "2.0"
}

# New configuration (v2.x.x)
config = {
    "processor_type": "advanced",
    "use_pattern_matching": True,
    "glue_version": "5.0"
}
```

## New Features in v2.x.x (Glue 5.0)
- Pattern matching for data processing
- Enhanced type hints
- Improved error messages
- Better performance with modern libraries
- Glue 5.0 specific optimizations
```

---

## AWS Glue Specific Considerations

### Runtime Constraints

AWS Glue has specific Python runtime versions:
- **Glue 2.0**: Python 3.7
- **Glue 3.0**: Python 3.9
- **Glue 4.0**: Python 3.10
- **Glue 5.0**: Python 3.11+

### Deployment Strategy

```python
# glue_job_deployment.py
import boto3
from typing import Dict, Any

def deploy_glue_job(job_name: str, python_version: str, script_location: str) -> Dict[str, Any]:
    """Deploy Glue job with appropriate library version."""
    
    glue_client = boto3.client('glue')
    
    # Determine library version based on Python runtime
    if python_version.startswith('3.7'):
        library_version = "aws-glue-datasource-lib>=1.0.0,<2.0.0"
    else:
        library_version = "aws-glue-datasource-lib>=2.0.0"
    
    job_config = {
        'Name': job_name,
        'Role': 'your-glue-role',
        'Command': {
            'Name': 'glueetl',
            'ScriptLocation': script_location,
            'PythonVersion': python_version
        },
        'DefaultArguments': {
            '--additional-python-modules': library_version,
            '--enable-metrics': '',
            '--enable-continuous-cloudwatch-log': 'true'
        },
        'GlueVersion': '5.0' if python_version != '3.7' else '2.0'
    }
    
    response = glue_client.create_job(**job_config)
    return response
```

### Testing with Glue Local Development

```python
# tests/integration/test_glue_local.py
import pytest
from moto import mock_glue
from glue_lib import GlueDataSourceConnector

@mock_glue
def test_glue_integration_py37():
    """Test integration with Glue 2.0 (Python 3.7)."""
    config = {
        "glue_version": "2.0",
        "python_version": "3.7",
        "compatibility_mode": True
    }
    
    connector = GlueDataSourceConnector(config)
    result = connector.process_data({"type": "table", "data": []})
    
    assert result is not None
    assert "processed" in result

@mock_glue  
def test_glue_integration_py311():
    """Test integration with Glue 5.0 (Python 3.11+)."""
    config = {
        "glue_version": "5.0", 
        "python_version": "3.11",
        "use_advanced_features": True
    }
    
    connector = GlueDataSourceConnector(config)
    result = connector.process_data({"type": "stream", "data": []})
    
    assert result is not None
    assert "advanced_processed" in result
```

---

## Implementation Examples

### Example 1: Conditional Feature Loading

```python
# src/glue_lib/__init__.py
from .compat import PYTHON_311_PLUS
from .core.connector import GlueDataSourceConnector
from .core.config import Config
from .core.exceptions import GlueLibError

# Version-specific exports
if PYTHON_311_PLUS:
    from .modern_features import AdvancedDataProcessor, PatternMatcher
    __all__ = [
        "GlueDataSourceConnector",
        "Config", 
        "GlueLibError",
        "AdvancedDataProcessor",
        "PatternMatcher"
    ]
else:
    from .legacy_features import BasicDataProcessor
    __all__ = [
        "GlueDataSourceConnector",
        "Config",
        "GlueLibError", 
        "BasicDataProcessor"
    ]

__version__ = "2.1.0" if PYTHON_311_PLUS else "1.5.0"
```

### Example 2: Graceful Degradation

```python
# src/glue_lib/core/data_processor.py
from typing import Any, Dict, List, Optional
from ..compat import PYTHON_311_PLUS, JSONType

class DataProcessor:
    """Data processor with graceful feature degradation."""
    
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self._setup_processor()
    
    def _setup_processor(self) -> None:
        """Setup processor based on available features."""
        if PYTHON_311_PLUS and self.config.get("use_advanced_features", True):
            self._use_pattern_matching = True
            self._use_modern_typing = True
        else:
            self._use_pattern_matching = False
            self._use_modern_typing = False
    
    def process_batch(self, items: List[JSONType]) -> List[JSONType]:
        """Process a batch of items."""
        if self._use_pattern_matching:
            return self._process_with_pattern_matching(items)
        else:
            return self._process_with_conditionals(items)
    
    def _process_with_pattern_matching(self, items: List[JSONType]) -> List[JSONType]:
        """Python 3.11+ pattern matching implementation."""
        results = []
        for item in items:
            match item:
                case {"type": "record", "data": data, "metadata": meta}:
                    results.append(self._process_record(data, meta))
                case {"type": "batch", "items": batch_items}:
                    results.extend(self.process_batch(batch_items))
                case {"error": error_msg}:
                    results.append({"error": f"Processed: {error_msg}"})
                case _:
                    results.append({"error": "Unknown item type"})
        return results
    
    def _process_with_conditionals(self, items: List[JSONType]) -> List[JSONType]:
        """Python 3.7 compatible conditional implementation."""
        results = []
        for item in items:
            if isinstance(item, dict):
                if item.get("type") == "record" and "data" in item:
                    metadata = item.get("metadata", {})
                    results.append(self._process_record(item["data"], metadata))
                elif item.get("type") == "batch" and "items" in item:
                    results.extend(self.process_batch(item["items"]))
                elif "error" in item:
                    results.append({"error": f"Processed: {item['error']}"})
                else:
                    results.append({"error": "Unknown item type"})
            else:
                results.append({"error": "Invalid item format"})
        return results
    
    def _process_record(self, data: Any, metadata: Dict[str, Any]) -> JSONType:
        """Process individual record."""
        return {
            "processed_data": data,
            "metadata": metadata,
            "processor_version": "advanced" if self._use_pattern_matching else "basic"
        }
```

### Example 3: Testing Strategy

```python
# tests/unit/test_compatibility.py
import pytest
import sys
from glue_lib.compat import PYTHON_311_PLUS
from glue_lib import GlueDataSourceConnector

class TestCompatibility:
    """Test compatibility across Python versions."""
    
    def test_basic_functionality_works_on_all_versions(self):
        """Ensure basic functionality works on all supported Python versions."""
        config = {"basic_mode": True}
        connector = GlueDataSourceConnector(config)
        
        test_data = {"type": "table", "data": [{"id": 1, "name": "test"}]}
        result = connector.process_data(test_data)
        
        assert result is not None
        assert "processed" in str(result).lower()
    
    @pytest.mark.skipif(not PYTHON_311_PLUS, reason="Python 3.11+ only feature")
    def test_advanced_features_python311(self):
        """Test advanced features available only in Python 3.11+."""
        config = {"use_advanced_features": True}
        connector = GlueDataSourceConnector(config)
        
        test_data = {"type": "stream", "data": []}
        result = connector.process_data(test_data)
        
        assert "advanced_processed" in result
    
    @pytest.mark.skipif(PYTHON_311_PLUS, reason="Python 3.7 compatibility test")
    def test_legacy_mode_python37(self):
        """Test legacy mode for Python 3.7."""
        config = {"compatibility_mode": True}
        connector = GlueDataSourceConnector(config)
        
        test_data = {"type": "table", "data": []}
        result = connector.process_data(test_data)
        
        assert "basic_processed" in result or "processed" in str(result).lower()
    
    def test_version_detection(self):
        """Test that version detection works correctly."""
        from glue_lib.compat import PYTHON_VERSION
        
        assert PYTHON_VERSION in [(3, 7), (3, 11)]
        assert isinstance(PYTHON_311_PLUS, bool)
```

---

## Conclusion

This comprehensive strategy provides multiple approaches for managing a Python library across different versions while maintaining compatibility with AWS Glue's runtime constraints. The recommended approach combines:

1. **Main branch for Python 3.7 stability** with `release/5.0` for modern features
2. **Single package with conditional dependencies** for easier maintenance
3. **Feature detection patterns** for runtime compatibility
4. **Comprehensive CI/CD testing** across all supported versions
5. **Clear documentation and migration guides** for users
6. **Semantic versioning** that reflects Python version compatibility (v1.x.x for Python 3.7, v2.x.x for Python 3.11+)

This approach prioritizes stability in the main branch while allowing innovation in the release/5.0 branch. Teams can choose the version that best fits their runtime requirements:
- **v1.x.x**: Stable, production-ready features for Python 3.7 (AWS Glue 2.0)
- **v2.x.x**: Modern features and Glue 5.0 optimizations for Python 3.11+ (AWS Glue 5.0)

Choose the specific strategies that best fit your team's workflow and maintenance capacity. Start with the conditional dependencies approach and feature detection patterns, as they provide the best balance of functionality and maintainability.
