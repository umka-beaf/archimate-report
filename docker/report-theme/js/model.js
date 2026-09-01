function setRootPanelHeight() {
    rootPanelHeight = $('.root-panel').outerHeight() || 0;
    rootPanelHeadingHeight = $('.root-panel-heading').outerHeight() || 0;
    $('.root-panel-body').css('height', rootPanelHeight - rootPanelHeadingHeight);
}

function strcmp(a, b){
	var aText = $(a).text().trim().toLowerCase();
	var bText = $(b).text().trim().toLowerCase();
	if (aText.toString() < bText.toString()) return -1;
  if (aText.toString() > bText.toString()) return 1;
  return 0;
}

// Sort a folder's direct children (folders first, then leaves) - done once
// per folder (guarded by the 'sorted' class) for performance reasons.
// Shared by toggleTreeEntry() and the default-expand step below.
function sortTreeFolder(listItem) {
	if ($(listItem).hasClass('sorted')) return;
	$(listItem).find(' > ul').each(function(){
		$(this).children('li.tree-folder').sort(strcmp).appendTo($(this));
		$(this).children('li.tree-element').sort(strcmp).appendTo($(this));
	});
	$(listItem).addClass('sorted');
}

// docker/report-theme: auto-expand the first level by default (the top-level
// "Model Content" / "Views" folders), so Business / Application / Technology
// / Views and the individual view names are visible right away instead of
// two clicks deep. Each layer's own elements stay collapsed until opened - a
// model can have hundreds of elements, so expanding everything by default
// would be unusable. Also re-applied after a search filter is cleared, so
// clearing the search doesn't leave the tree fully collapsed again.
function expandFirstLevel() {
	$('.tree > li.parent_li').each(function () {
		sortTreeFolder(this);
		$(this).find('> span > i').removeClass('glyphicon-triangle-right').addClass('glyphicon-triangle-bottom');
	});
	$('.tree li.parent_li').not('.tree > li').find(' > ul > li').hide();
}

function toggleTreeEntry(listItem) {
	sortTreeFolder(listItem);

	if (isTreeFiltered()) {
		return;
	} else {
		var children = $(listItem).find(' > ul > li');
		if (children.is(":visible")) {
			children.hide('fast');
			// Toggle arrow icon
			$(listItem).find('> span > i').addClass('glyphicon-triangle-right').removeClass('glyphicon-triangle-bottom');
		} else {
			children.show('fast');
			// Toggle arrow icon
			$(listItem).find('> span > i').addClass('glyphicon-triangle-bottom').removeClass('glyphicon-triangle-right');
		}
	}
}

/* ==========================================================================
   docker/report-theme: language + light/dark theme preferences.
   Same small block is duplicated in js/frame.js, since every generated page
   (index.html, elements/*.html, views/*.html) is its own <html> document -
   there is no single shared entry point to hook into without patching
   Archi's page templates, so each of the two static JS files applies the
   stored preference to whichever document it happens to run in.
   ========================================================================== */

function arcApplyPreferences() {
	var storedLang = localStorage.getItem('archi-report-lang');
	var lang = storedLang || (((navigator.language || 'ru').slice(0, 2).toLowerCase() === 'en') ? 'en' : 'ru');
	document.documentElement.lang = lang;

	var storedTheme = localStorage.getItem('archi-report-theme');
	var theme = storedTheme || ((window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) ? 'dark' : 'light');
	document.documentElement.classList.toggle('dark', theme === 'dark');

	return { lang: lang, theme: theme };
}

function arcUpdateToggleUI() {
	var current = arcApplyPreferences();
	document.querySelectorAll('[data-arc-lang]').forEach(function (btn) {
		btn.classList.toggle('active', btn.getAttribute('data-arc-lang') === current.lang);
	});
	var themeBtn = document.querySelector('[data-arc-theme-toggle]');
	if (themeBtn) themeBtn.textContent = current.theme === 'dark' ? '☀' : '☽';
}

// Push a newly-changed preference into the already-loaded view/element
// iframes too (their own frame.js will pick it up on next navigation anyway,
// but this avoids waiting for a click on a tree entry to see the effect).
function arcApplyToVisibleFrames() {
	['view', 'element'].forEach(function (name) {
		try {
			var frameWin = window.frames[name];
			var frameDoc = frameWin && frameWin.document;
			if (frameDoc && frameDoc.documentElement) {
				var storedLang = localStorage.getItem('archi-report-lang');
				var storedTheme = localStorage.getItem('archi-report-theme');
				if (storedLang) frameDoc.documentElement.lang = storedLang;
				if (storedTheme) frameDoc.documentElement.classList.toggle('dark', storedTheme === 'dark');
			}
		} catch (e) {
			// cross-frame not ready yet - harmless, the frame applies its
			// own stored preference on its next load anyway
		}
	});
}

function arcSetLang(lang) {
	localStorage.setItem('archi-report-lang', lang);
	arcUpdateToggleUI();
	arcApplyToVisibleFrames();
}

function arcSetTheme(theme) {
	localStorage.setItem('archi-report-theme', theme);
	arcUpdateToggleUI();
	arcApplyToVisibleFrames();
}

function appendThemeAndLangToggle() {
	var nav = document.querySelector('.navbar-nav.navbar-right');
	if (!nav) return;

	var li = document.createElement('li');
	li.innerHTML =
		'<div class="arc-toggle-group">' +
			'<span class="arc-toggle-btn" data-arc-lang="ru" title="Русский">RU</span>' +
			'<span class="arc-toggle-btn" data-arc-lang="en" title="English">EN</span>' +
			'<span class="arc-toggle-btn" data-arc-theme-toggle title="Light / Dark"></span>' +
		'</div>';
	nav.insertBefore(li, nav.firstChild);

	li.querySelectorAll('[data-arc-lang]').forEach(function (btn) {
		btn.addEventListener('click', function () {
			arcSetLang(btn.getAttribute('data-arc-lang'));
		});
	});
	li.querySelector('[data-arc-theme-toggle]').addEventListener('click', function () {
		var current = document.documentElement.classList.contains('dark') ? 'dark' : 'light';
		arcSetTheme(current === 'dark' ? 'light' : 'dark');
	});

	arcUpdateToggleUI();
}

// index.html is the only page the browser tab itself renders (elements/*.html
// and views/*.html load inside an iframe via frame.js, whose favicon a tab
// never shows) - so this is the one place worth adding explicit <link
// rel="icon"> tags. generate.sh already drops the actual files (favicon.ico
// + PNGs) into the report root unconditionally; these tags just point modern
// browsers/OSes at the higher-res PNG variants instead of the bare .ico.
function appendFaviconLinks() {
	var head = document.head;
	if (!head || document.querySelector('link[rel="icon"]')) return;

	[
		['icon', 'image/png', '32x32', 'favicon-32.png'],
		['icon', 'image/png', '192x192', 'favicon-192.png'],
		['apple-touch-icon', null, '180x180', 'apple-touch-icon.png']
	].forEach(function (entry) {
		var link = document.createElement('link');
		link.rel = entry[0];
		if (entry[1]) link.type = entry[1];
		link.sizes = entry[2];
		link.href = entry[3];
		head.appendChild(link);
	});
}

$(document).ready(function() {
	// Apply stored/detected language + theme before anything else paints
	arcApplyPreferences();
	appendThemeAndLangToggle();
	appendFaviconLinks();

	// Set jQuery UI Layout panes
  $('body').layout({
    minSize: 45,
    maskContents: true,
    north: {
      size: 45,
      spacing_open: 0,
      closable: false,
      resizable: false
    },
    west: {
			size: 430,
			spacing_open: 8
		},
    west__childOptions: {
      maskContents: true,
      south: {
	      /* docker/report-theme: the default 250/100 split left the element
	         details panel (Documentation/Properties/Analysis) cramped,
	         especially now that Documentation renders as full Markdown
	         (headings, tables) instead of a short text blob. Give it roughly
	         half the west column by default; still user-resizable. */
	      minSize: 180,
				size: 420,
				spacing_open: 8
			},
			center: {
				minSize: 120,
				onresize: "setRootPanelHeight"
			}
    }
  });

	// Set heigh of panels the first time
	setRootPanelHeight();

	// Remove hidden nodes from the model tree
	$('.hide-true').remove();
	let topTreeFolders = $('.tree > li');
	topTreeFolders.each(function(index) {
		if (! $(this).find(' > ul > li').length) {
			$(this).remove();
		}
	});


	// Setup modeltree
	$('.tree li:has(ul)').addClass('parent_li');
	expandFirstLevel();

	// Add show/hide function on modeltree
	$('.tree li.parent_li > span').on('click', function (e) {
		toggleTreeEntry($(this).parent('li.parent_li'));
		e.stopPropagation();
	});

	// *** SEARCH ***
	appendSearchBar();


	// *** DEEP LINKS ***

	// Register a new onClick function
	let $viewLinks = $("a[href][target='view']");
	$viewLinks.on('click', function (event) {
		const id = getIdFromHref(event.currentTarget.href);
		setLocationForView(id);
		openViewFromLocation(false);
		event.stopPropagation();
		return false;
	});

	function setLocationForView(id) {
		const url = new URL(window.location);
		url.searchParams.set('view', id);
		window.history.pushState({}, '', url);
	}

	function getIdFromHref(href) {
		return href.split("/").pop().slice(0, -5);
	}

	function getIdFromLocation() {
		const url = new URL(window.location);
		return url.searchParams.get('view');
	}

	function openViewFromLocation(expandModelTree) {
		// Find matching view in model tree...
		const targetId = getIdFromLocation();
		const matchingLinks = $viewLinks.filter(function (index, element) {
			return getIdFromHref(element.href) === targetId;
		});
		const link = matchingLinks[0];

		if (link) {
			// View found in model tree. Loading it in frame
			const $link = $(link);
			$("iframe[name='view']").attr('src', $link.attr('href'));

			if (expandModelTree) {
				let spans = [];
				let $parentListItem = $link.parent().parent().parent();
				while ($parentListItem[0].tagName === 'LI') {
					spans.push($parentListItem.children().first());
					$parentListItem = $parentListItem.parent().parent();
				}
				while (spans.length) {
					spans.pop().click();
				}
			}
		}
	}

	$(window).on('message', function (e) {
		const id = e.originalEvent.data.split('=').pop();
		setLocationForView(id);
		//openViewFromLocation(true);
	});

	// Load initial view id on page load
	openViewFromLocation(true);

});


function appendSearchBar() {
	let newSearchDiv = '<div id="searchBox"><input type="text" id="tree-search" placeholder="Search..." /></div>';

	document.getElementsByClassName("panel-heading")[0].innerHTML += newSearchDiv;

	document.querySelector('#tree-search').onkeyup = function(e) {
		if (e.key !== 'Enter' && e.keyCode !== 13)
			return;
		else
			searchInViews();
	};
}

function isTreeFiltered() {
	return $('#tree-search').hasClass('filtered');
}

function searchInViews() {
	const filter = $('#tree-search').val();

	// Hide all entries
	listItems = $('.tree li');
	listItems.hide();
	listItems.find(' > span > i').addClass('glyphicon-triangle-right').removeClass('glyphicon-triangle-bottom');

	// Is a filter set?
	if (filter.length === 0) {
		// No: show the top level entries ('Model Content' and 'Views') and stop here
		$('.tree > li').show();
		expandFirstLevel();
		$('#tree-search').removeClass('filtered');
		document.querySelector('#tree-search').title = "";
		return;
	}

	// Yes: set the 'filtered' flag and filter the model tree
	$('#tree-search').addClass('filtered');
	document.querySelector('#tree-search').title = "To clear filter, empty this field and press ENTER";

	// Get model tree
	let modelTree = $('.tree');

	// Case insensitive search (a 'li' matches if itself or its children match)
	let foundItems = modelTree.find("li").filter(function () {
		let reg = new RegExp(filter, "ig");
		let content = $(this).hasClass('tree-element') ? $(this) : $(this).find('li.tree-element');
		return reg.test(content.text());
	});

	// Show matching entries
	foundItems.show();
	foundItems.parent("ul").parent("li").find("> span > i").addClass('glyphicon-triangle-bottom').removeClass('glyphicon-triangle-right');
}
