enum ProjectType {
  defaultType('Plain files', 'Write HTML directly (no build process)'),
  eleventy('11ty', 'Eleventy static site generator'),
  hugo('Hugo', 'Hugo static site generator');

  final String displayName;
  final String description;

  const ProjectType(this.displayName, this.description);
}

class ProjectTemplate {
  final ProjectType type;

  ProjectTemplate(this.type);

  Map<String, dynamic> generatePackageJson(String projectName) {
    switch (type) {
      case ProjectType.defaultType:
        return {
          'name': projectName,
          'scripts': {
            'start': 'bun x @xmit-co/bob preview',
          },
        };

      case ProjectType.eleventy:
        return {
          'name': projectName,
          'scripts': {
            'build': 'eleventy',
            'start': 'eleventy --serve',
          },
        };

      case ProjectType.hugo:
        return {
          'name': projectName,
          'scripts': {
            'build': 'bun x hugo-extended build',
            'start': 'bun x hugo-extended server',
          },
          'devDependencies': {
            'hugo-extended': '^0',
          },
        };
    }
  }
}
