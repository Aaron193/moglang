// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import { mogShikiOptions } from './mog-language.mjs';

const site = process.env.SITE_URL || 'https://moglang.dev';
const base = process.env.BASE_PATH || undefined;
const editBaseUrl = process.env.MOG_SITE_EDIT_BASE_URL;

export default defineConfig({
	site,
	base,
	integrations: [
		starlight({
			title: 'Mog',
			description:
				'Mog is a strictly typed, bytecode-compiled programming language with a VM, REPL, native packages, and editor tooling.',
			tagline: 'A sharp programming language for people who want the toolchain to take them seriously.',
			expressiveCode: {
				shiki: mogShikiOptions,
			},
			logo: {
				src: '../../tooling/vscode-mog/images/fileicons/moglang-icon-option-3.svg',
				alt: 'Mog',
			},
			customCss: ['./src/styles/site.css'],
			favicon: '/mog-logo.svg',
			pagefind: true,
			lastUpdated: true,
			disable404Route: true,
			editLink: editBaseUrl ? { baseUrl: editBaseUrl } : undefined,
			head: [
				{
					tag: 'meta',
					attrs: {
						name: 'theme-color',
						content: '#111D4F',
					},
				},
			],
			sidebar: [
				{
					label: 'Overview',
					items: [
						{ label: 'Docs Home', slug: 'docs' },
					],
				},
				{
					label: 'Getting Started',
					items: [
						{ label: 'Install Mog', slug: 'docs/getting-started/install' },
						{ label: 'Quickstart', slug: 'docs/getting-started/quickstart' },
					],
				},
				{
					label: 'Language',
					items: [
						{ label: 'Language Overview', slug: 'docs/language/basics' },
						{ label: 'Values and Bindings', slug: 'docs/language/values-and-bindings' },
						{ label: 'Built-in Types and Casts', slug: 'docs/language/built-in-types-and-casts' },
						{ label: 'Control Flow', slug: 'docs/language/control-flow' },
						{ label: 'Collections', slug: 'docs/language/collections' },
						{ label: 'Functions and Closures', slug: 'docs/language/functions-and-closures' },
						{ label: 'Types and Inheritance', slug: 'docs/language/types-and-inheritance' },
						{ label: 'Modules and Imports', slug: 'docs/language/modules-and-imports' },
						{
							label: 'Nullability and Type Checking',
							slug: 'docs/language/nullability-and-typechecking',
						},
					],
				},
				{
					label: 'Tooling',
					items: [
						{ label: 'Tooling Overview', slug: 'docs/tooling/cli-repl-vscode-lsp' },
						{ label: 'CLI and Debug Flags', slug: 'docs/tooling/cli-and-debug-flags' },
						{ label: 'REPL', slug: 'docs/tooling/repl' },
						{ label: 'VS Code and LSP', slug: 'docs/tooling/vscode-and-lsp' },
					],
				},
				{
					label: 'Packages',
					items: [
						{ label: 'Packages Overview', slug: 'docs/packages/imports-native-packages' },
						{ label: 'Official Packages', slug: 'docs/packages/official-packages' },
						{ label: 'Using Native Packages', slug: 'docs/packages/using-native-packages' },
						{ label: 'Authoring Native Packages', slug: 'docs/packages/authoring-native-packages' },
					],
				},
				{
					label: 'Examples',
					items: [{ label: 'Example Programs', slug: 'docs/examples' }],
				},
				{
					label: 'Reference',
					items: [
						{ label: 'Reference Overview', slug: 'docs/reference/syntax-builtins-flags' },
						{ label: 'Syntax Rules', slug: 'docs/reference/syntax-rules' },
						{ label: 'Built-in Functions', slug: 'docs/reference/built-in-functions' },
						{ label: 'Release Notes', slug: 'docs/reference/releases' },
					],
				},
			],
		}),
	],
});
