class FilteredSearchSpecHelper {
  static createFilterVisualTokenHTML(name, value, isSelected) {
    return FilteredSearchSpecHelper.createFilterVisualToken(name, value, isSelected).outerHTML;
  }

  static createFilterVisualToken(name, value, isSelected = false) {
    const li = document.createElement('li');
    li.classList.add('js-visual-token');
    li.classList.add('filtered-search-token');

    li.innerHTML = `
      <div class="selectable ${isSelected ? 'selected' : ''}" role="button">
        <div class="name">${name}</div>
        <div class="value">${value}</div>
      </div>
    `;

    return li;
  }

  static createNameFilterVisualTokenHTML(name) {
    return `
      <li class="js-visual-token filtered-search-token">
        <div class="name">${name}</div>
      </li>
    `;
  }

  static createSearchVisualTokenHTML(name) {
    return `
      <li class="js-visual-token filtered-search-term">
        <div class="name">${name}</div>
      </li>
    `;
  }

  static createInputHTML(placeholder) {
    return `
      <li>
        <input type='text' class='filtered-search' placeholder='${placeholder || ''}' />
      </li>
    `;
  }

  static createTokensContainerHTML(html, inputPlaceholder) {
    return `
      ${html}
      ${FilteredSearchSpecHelper.createInputHTML(inputPlaceholder)}
    `;
  }
}

module.exports = FilteredSearchSpecHelper;
