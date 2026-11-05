import { Link } from 'react-router-dom';
import { useBusinessTitle } from '../hooks';

/** A page of Izzy Clipz Business that isn't there: a friendly line, and the way to Today or sign-in. */
export function NotFound({ signedIn }: { signedIn: boolean }) {
  useBusinessTitle('Page not found');
  return (
    <div className="container container--narrow biz-not-found">
      <h1>This page isn't here.</h1>
      <p className="lead secondary">It may have moved. Izzy Clipz Business has Today, Analytics, Products and Settings.</p>
      <Link className="button button--primary button--large" to={signedIn ? '/business/today' : '/business'}>
        {signedIn ? 'Go to Today' : 'Sign in'}
      </Link>
    </div>
  );
}
