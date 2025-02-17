import { SectionSlug } from 'data/types';
import { makeRequest } from './common';

// eslint-disable-next-line
export type ExtrinsicRead = Object;

// eslint-disable-next-line
export type KeyValues = Object;
export type ExtrinsicUpsert = {
  result: 'success';
};
export type ExtrinsicDelete = {
  result: 'success';
};

export function readGlobal(keys: string[] | null = null) {
  const params = {
    method: 'GET',
    url: '/state' + toKeyParams(keys),
  };

  return makeRequest<ExtrinsicRead>(params);
}

export const readGlobalUserState = async (
  keys: string[] | null = null,
  useLocalStorage = false,
) => {
  let result: any = {};
  if (useLocalStorage) {
    // localStorage API doesn't support the "get all" behavior, so we need to put everything into a single object
    const storedUserState = JSON.parse(localStorage.getItem('torus.userState') || '{}');
    if (keys) {
      keys.forEach((key) => {
        result[key] = storedUserState[key];
      });
    } else {
      result = storedUserState;
    }
  } else {
    const serverUserState = await readGlobal(keys);
    // merge server state with result
    if ((serverUserState as any).type !== 'ServerError') {
      result = serverUserState;
    }
  }
  return result;
};

export const updateGlobalUserState = async (
  updates: { [topKey: string]: { [key: string]: any } },
  useLocalStorage = false,
) => {
  const topLevelKeys = Object.keys(updates);
  const currentState = await readGlobalUserState(topLevelKeys, useLocalStorage);

  const newState = { ...currentState };
  topLevelKeys.forEach((topKey) => {
    const actualKeys = Object.keys(updates[topKey]);
    actualKeys.forEach((actualKey) => {
      newState[topKey] = { ...newState[topKey], [actualKey]: updates[topKey][actualKey] };
    });
  });

  if (useLocalStorage) {
    const existingState = localStorage.getItem('torus.userState') || '{}';
    const parsedState = JSON.parse(existingState);

    const mergedState = { ...parsedState, ...newState };

    localStorage.setItem('torus.userState', JSON.stringify(mergedState));
  } else {
    await upsertGlobal(newState);
  }
  return newState;
};

export function deleteGlobal(keys: string[]) {
  const params = {
    method: 'DELETE',
    url: '/state' + toKeyParams(keys),
  };

  return makeRequest<ExtrinsicRead>(params);
}

export function upsertGlobal(keyValues: KeyValues) {
  const params = {
    method: 'PUT',
    body: JSON.stringify(keyValues),
    url: '/state',
  };

  return makeRequest<ExtrinsicDelete>(params);
}

export function readSection(slug: SectionSlug, keys: string[] | null = null) {
  const params = {
    method: 'GET',
    url: `/state/course/${slug}` + toKeyParams(keys),
  };

  return makeRequest<ExtrinsicRead>(params);
}

export function deleteSection(slug: SectionSlug, keys: string[]) {
  const params = {
    method: 'DELETE',
    url: `/state/course/${slug}` + toKeyParams(keys),
  };

  return makeRequest<ExtrinsicRead>(params);
}

export function upsertSection(slug: SectionSlug, keyValues: KeyValues) {
  const params = {
    method: 'PUT',
    body: JSON.stringify(keyValues),
    url: `/state/course/${slug}`,
  };

  return makeRequest<ExtrinsicDelete>(params);
}

// Take a list of string key names and turn it into the form expected by
// Phoenix: foo[]=bar&foo[]=baz&foo[]=qux.
function toKeyParams(keys: string[] | null = null) {
  return keys === null
    ? ''
    : '?' +
        keys
          .reduce((p, k) => {
            return p + '&keys[]=' + k;
          }, '')
          .substr(1);
}
